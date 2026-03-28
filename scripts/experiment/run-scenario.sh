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

SCENARIO_NAME="${SCENARIO_NAME:-$(basename -- "$SCENARIO_FILE" .yaml)}"
RUN_DIR="$(new_run_dir "$SCENARIO_NAME")"
TP_LOG_DIR="$RUN_DIR/tp"
INJECTION_DIR="$RUN_DIR/injection"
OBS_DIR="$RUN_DIR/observability"
SUMMARY_FILE="$RUN_DIR/run-summary.env"
mkdir -p "$TP_LOG_DIR" "$INJECTION_DIR" "$OBS_DIR"

printf 'scenario_name=%s\n' "$SCENARIO_NAME" > "$SUMMARY_FILE"
printf 'scenario_file=%s\n' "$SCENARIO_FILE" >> "$SUMMARY_FILE"
printf 'run_dir=%s\n' "$RUN_DIR" >> "$SUMMARY_FILE"
printf 'started_at=%s\n' "$(date --iso-8601=seconds)" >> "$SUMMARY_FILE"

if [[ "${DOCKER_MODE:-compose}" == "compose" ]]; then
  start_args=()
  if [[ "${FULL_OBSERVABILITY:-false}" == "true" ]]; then
    start_args+=(--full-observability)
  fi
  start_args+=(--apply-sql "${SQL_PRESET:-sql/tuning/baseline_params.sql}")
  "$REPO_ROOT/scripts/db/start.sh" "${start_args[@]}"
fi

if [[ "${TP_RUNNER:-sysbench}" == "sysbench" ]]; then
  "$REPO_ROOT/scripts/benchmark/run-sysbench.sh" --mode prepare --tables "${SYSBENCH_TABLES:-8}" --table-size "${SYSBENCH_TABLE_SIZE:-50000}" --threads "${SYSBENCH_THREADS:-64}" --time 30 --output "$TP_LOG_DIR/sysbench-prepare.log"
else
  "$REPO_ROOT/scripts/benchmark/load-tpcc.sh" --scalefactor "${TPCC_SCALEFACTOR:-10}" --terminals "${TPCC_TERMINALS:-32}" --duration "${DURATION_SECONDS:-300}" --output "$TP_LOG_DIR/tpcc-load.log"
fi

if [[ "${LOAD_TPCH_DATA:-true}" == "true" ]]; then
  "$REPO_ROOT/scripts/benchmark/load-tpch.sh" --scale-factor "${TPCH_SCALE_FACTOR:-1}"
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

if [[ "${TP_RUNNER:-sysbench}" == "sysbench" ]]; then
  "$REPO_ROOT/scripts/benchmark/run-sysbench.sh" \
    --mode run \
    --tables "${SYSBENCH_TABLES:-8}" \
    --table-size "${SYSBENCH_TABLE_SIZE:-50000}" \
    --threads "${SYSBENCH_THREADS:-64}" \
    --report-interval "${SYSBENCH_REPORT_INTERVAL:-1}" \
    --time "${DURATION_SECONDS:-180}" \
    --output "$TP_LOG_DIR/sysbench-run.log"
else
  "$REPO_ROOT/scripts/benchmark/run-tpcc.sh" \
    --scalefactor "${TPCC_SCALEFACTOR:-10}" \
    --terminals "${TPCC_TERMINALS:-32}" \
    --duration "${DURATION_SECONDS:-300}" \
    --output "$TP_LOG_DIR/tpcc-run.log"
fi

if [[ -n "$INJECTION_PID" ]]; then
  wait "$INJECTION_PID"
fi

kill "$OBS_PID" >/dev/null 2>&1 || true
unset OBS_PID

"$REPO_ROOT/scripts/observe/export-run-artifacts.sh" --run-dir "$RUN_DIR"
"$REPO_ROOT/scripts/experiment/validate-targets.sh" --run-dir "$RUN_DIR" --summary-file "$SUMMARY_FILE" || true
"$REPO_ROOT/scripts/experiment/compare-runs.sh" --run-dir "$RUN_DIR" || true

printf 'finished_at=%s\n' "$(date --iso-8601=seconds)" >> "$SUMMARY_FILE"
printf 'run complete: %s\n' "$RUN_DIR"
