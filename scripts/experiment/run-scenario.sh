#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

SCENARIO_FILE="${1:-}"
[[ -n "$SCENARIO_FILE" ]] || fail "usage: $0 <scenario-yaml>"

ensure_env_file
load_flat_yaml "$REPO_ROOT/experiments/configs/base/environment.yaml"
load_flat_yaml "$REPO_ROOT/experiments/configs/base/database.yaml"
load_flat_yaml "$REPO_ROOT/experiments/configs/base/workloads.yaml"
load_flat_yaml "$REPO_ROOT/$SCENARIO_FILE"

if [[ -n "${DATASET_PROFILE_FILE:-}" ]]; then
  load_flat_yaml "$REPO_ROOT/$DATASET_PROFILE_FILE"
fi

if [[ -n "${HARDWARE_PROFILE_FILE:-}" ]]; then
  load_flat_yaml "$REPO_ROOT/$HARDWARE_PROFILE_FILE"
fi

load_flat_yaml "$REPO_ROOT/$SCENARIO_FILE"

SCENARIO_NAME="${SCENARIO_NAME:-$(basename -- "$SCENARIO_FILE" .yaml)}"
RUN_DIR="$(new_run_dir "$SCENARIO_NAME")"
RUN_ID="$(basename -- "$RUN_DIR")"
TP_LOG_DIR="$RUN_DIR/tp"
INJECTION_DIR="$RUN_DIR/injection"
OBS_DIR="$RUN_DIR/observability"
SUMMARY_FILE="$RUN_DIR/run-summary.env"
mkdir -p "$TP_LOG_DIR" "$INJECTION_DIR" "$OBS_DIR"

printf 'scenario_name=%s\n' "$SCENARIO_NAME" > "$SUMMARY_FILE"
printf 'scenario_file=%s\n' "$SCENARIO_FILE" >> "$SUMMARY_FILE"
printf 'run_dir=%s\n' "$RUN_DIR" >> "$SUMMARY_FILE"
printf 'run_id=%s\n' "$RUN_ID" >> "$SUMMARY_FILE"
printf 'tp_runner=%s\n' "${TP_RUNNER:-sysbench}" >> "$SUMMARY_FILE"
printf 'started_at=%s\n' "$(date --iso-8601=seconds)" >> "$SUMMARY_FILE"

if [[ "${DOCKER_MODE:-compose}" == "compose" ]]; then
  start_args=()
  if [[ "${FULL_OBSERVABILITY:-false}" == "true" ]]; then
    start_args+=(--full-observability)
  fi
  start_args+=(--apply-sql "${SQL_PRESET:-sql/tuning/baseline_params.sql}")
  "$REPO_ROOT/scripts/db/start.sh" "${start_args[@]}"
fi

case "${TP_RUNNER:-sysbench}" in
  sysbench)
    log "Preparing sysbench data..."
    "$REPO_ROOT/scripts/benchmark/run-sysbench.sh" --mode prepare --tables "${SYSBENCH_TABLES:-8}" --table-size "${SYSBENCH_TABLE_SIZE:-50000}" --threads "${SYSBENCH_THREADS:-64}" --time 30 --output "$TP_LOG_DIR/sysbench-prepare.log"
    log "Sysbench data preparation complete"
    ;;
  tpcc)
    log "Loading TPCC data..."
    "$REPO_ROOT/scripts/benchmark/load-tpcc.sh" --scalefactor "${TPCC_SCALEFACTOR:-10}" --terminals "${TPCC_TERMINALS:-32}" --duration "${DURATION_SECONDS:-300}" --output "$TP_LOG_DIR/tpcc-load.log"
    log "TPCC data loading complete"
    ;;
  tpch)
    log "TPCH primary workload selected; skipping TP prepare stage"
    ;;
  *)
    fail "unsupported tp_runner: ${TP_RUNNER:-sysbench}"
    ;;
esac

if [[ "${LOAD_TPCH_DATA:-true}" == "true" ]]; then
  tpch_load_args=(--scale-factor "${TPCH_SCALE_FACTOR:-1}")
  if [[ -n "${TPCH_DATA_POLICY:-}" ]]; then
    tpch_load_args+=(--data-policy "${TPCH_DATA_POLICY}")
  fi
  if [[ -n "${TPCH_SEED_NAME:-}" ]]; then
    tpch_load_args+=(--seed-name "${TPCH_SEED_NAME}")
  fi
  "$REPO_ROOT/scripts/benchmark/load-tpch.sh" "${tpch_load_args[@]}"
fi

"$REPO_ROOT/scripts/observe/sample-db-memory.sh" --interval "${OBSERVE_INTERVAL_SECONDS:-15}" --output "$OBS_DIR/db-memory.tsv" &
OBS_PID=$!

cleanup() {
  if [[ -n "${OBS_PID:-}" ]]; then
    kill "$OBS_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "${ENABLE_INJECTION:-true}" == "true" ]]; then
  total_injection_delay="$(( ${WARMUP_SECONDS:-0} + ${INJECTION_DELAY_SECONDS:-60} ))"
  "$REPO_ROOT/scripts/benchmark/inject-slow-sql.sh" \
    --delay "$total_injection_delay" \
    --query-dir "$REPO_ROOT/${INJECTION_QUERY_DIR:-benchmarks/tpch/variants/pressure-injection}" \
    --repeat "${INJECTION_REPEAT:-1}" \
    --output-dir "$INJECTION_DIR" &
  INJECTION_PID=$!
else
  INJECTION_PID=""
fi

case "${TP_RUNNER:-sysbench}" in
  sysbench)
    "$REPO_ROOT/scripts/benchmark/run-sysbench.sh" \
      --mode run \
      --tables "${SYSBENCH_TABLES:-8}" \
      --table-size "${SYSBENCH_TABLE_SIZE:-50000}" \
      --threads "${SYSBENCH_THREADS:-64}" \
      --report-interval "${SYSBENCH_REPORT_INTERVAL:-1}" \
      --time "${DURATION_SECONDS:-180}" \
      --output "$TP_LOG_DIR/sysbench-run.log"
    ;;
  tpcc)
    "$REPO_ROOT/scripts/benchmark/run-tpcc.sh" \
      --scalefactor "${TPCC_SCALEFACTOR:-10}" \
      --terminals "${TPCC_TERMINALS:-32}" \
      --duration "${DURATION_SECONDS:-300}" \
      --output "$TP_LOG_DIR/tpcc-run.log"
    ;;
  tpch)
    tpch_args=(--output-dir "$TP_LOG_DIR/tpch")
    if [[ -n "${TPCH_QUERY_FILE:-}" ]]; then
      tpch_args+=(--query-file "$REPO_ROOT/${TPCH_QUERY_FILE}")
    else
      tpch_args+=(--query-dir "$REPO_ROOT/${TPCH_QUERY_DIR:-benchmarks/tpch/variants/spill-prone}")
    fi
    "$REPO_ROOT/scripts/benchmark/run-tpch.sh" "${tpch_args[@]}"
    ;;
  *)
    fail "unsupported tp_runner: ${TP_RUNNER:-sysbench}"
    ;;
esac

if [[ -n "$INJECTION_PID" ]]; then
  wait "$INJECTION_PID"
fi

kill "$OBS_PID" >/dev/null 2>&1 || true
unset OBS_PID

if [[ "${TP_RUNNER:-sysbench}" == "tpch" && -d "$TP_LOG_DIR/tpch" ]] && compgen -G "$TP_LOG_DIR/tpch/*.plan" > /dev/null; then
  "$REPO_ROOT/scripts/benchmark/analyze-plan-batch.sh" \
    --input-dir "$TP_LOG_DIR/tpch" \
    --output-dir "$RUN_DIR/plan-analysis/tpch" \
    --analysis-name tpch \
    --run-id "$RUN_ID" \
    --scenario-name "$SCENARIO_NAME" || true
fi

if [[ -d "$INJECTION_DIR" ]]; then
  shopt -s nullglob
  for query_dir in "$INJECTION_DIR"/*; do
    [[ -d "$query_dir" ]] || continue
    if compgen -G "$query_dir/*.plan" > /dev/null; then
      analysis_name="$(basename -- "$query_dir")"
      "$REPO_ROOT/scripts/benchmark/analyze-plan-batch.sh" \
        --input-dir "$query_dir" \
        --output-dir "$RUN_DIR/plan-analysis/$analysis_name" \
        --analysis-name "$analysis_name" \
        --run-id "$RUN_ID" \
        --scenario-name "$SCENARIO_NAME" || true
    fi
  done
  shopt -u nullglob
fi

"$REPO_ROOT/scripts/observe/export-run-artifacts.sh" --run-dir "$RUN_DIR"
"$REPO_ROOT/scripts/experiment/validate-targets.sh" --run-dir "$RUN_DIR" --summary-file "$SUMMARY_FILE" || true
"$REPO_ROOT/scripts/experiment/compare-runs.sh" --run-dir "$RUN_DIR" || true

printf 'finished_at=%s\n' "$(date --iso-8601=seconds)" >> "$SUMMARY_FILE"
printf 'run complete: %s\n' "$RUN_DIR"
