#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

QUERY_DIR="$REPO_ROOT/benchmarks/tpch/variants/spill-prone"
QUERY_FILE=""
OUTPUT_DIR="$REPO_ROOT/experiments/reports/tpch-run"
PLAN_MODE="analyze"
QUERY_TIMEOUT_SECONDS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query-dir)
      QUERY_DIR="$2"
      shift
      ;;
    --query-file)
      QUERY_FILE="$2"
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift
      ;;
    --plan-mode)
      PLAN_MODE="$2"
      shift
      ;;
    --query-timeout-seconds)
      QUERY_TIMEOUT_SECONDS="$2"
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

ensure_env_file
SUMMARY_FILE="$OUTPUT_DIR/summary.tsv"
mkdir -p "$OUTPUT_DIR"
printf 'query_name\tduration_seconds\tplan_status\trun_status\texit_code\tlog_file\tplan_file\n' > "$SUMMARY_FILE"

classify_status() {
  local exit_code="$1"
  local output_file="$2"
  if [[ "$exit_code" -eq 0 ]]; then
    printf 'completed\n'
  elif grep -qi 'statement timeout' "$output_file" 2>/dev/null; then
    printf 'timed_out\n'
  else
    printf 'failed\n'
  fi
}

run_sql_batch() {
  local output_file="$1"
  local body="$2"
  local exit_code=0

  set +e
  {
    if [[ "$QUERY_TIMEOUT_SECONDS" -gt 0 ]]; then
      printf "SET statement_timeout = '%ss';\n" "$QUERY_TIMEOUT_SECONDS"
    fi
    printf '%s\n' "$body"
  } | compose exec -T -u "$DB_CONTAINER_USER" "$DB_SERVICE_NAME" "$DB_CLIENT_BIN" -v ON_ERROR_STOP=1 -d "$DB_NAME" > "$output_file" 2>&1
  exit_code=$?
  set -e

  return "$exit_code"
}

run_one() {
  local sql_file="$1"
  local query_name="$(basename -- "$sql_file")"
  local log_file="$OUTPUT_DIR/${query_name%.sql}.log"
  local plan_file="$OUTPUT_DIR/${query_name%.sql}.plan"
  local started="$(date +%s)"
  local sql_content
  local plan_sql=""
  local plan_exit=0
  local run_exit=0
  local plan_status="skipped"
  local run_status="skipped"

  sql_content="$(cat "$sql_file")"

  case "$PLAN_MODE" in
    skip)
      : > "$plan_file"
      ;;
    plain)
      plan_sql="EXPLAIN $sql_content"
      run_sql_batch "$plan_file" "$plan_sql" || plan_exit=$?
      plan_status="$(classify_status "$plan_exit" "$plan_file")"
      ;;
    analyze)
      plan_sql="EXPLAIN ANALYZE $sql_content"
      run_sql_batch "$plan_file" "$plan_sql" || plan_exit=$?
      plan_status="$(classify_status "$plan_exit" "$plan_file")"
      ;;
    *)
      fail "unknown plan mode: $PLAN_MODE"
      ;;
  esac

  run_sql_batch "$log_file" "$sql_content" || run_exit=$?
  run_status="$(classify_status "$run_exit" "$log_file")"

  local finished="$(date +%s)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$query_name" "$((finished - started))" "$plan_status" "$run_status" "$run_exit" "$log_file" "$plan_file" >> "$SUMMARY_FILE"
}

if [[ -n "$QUERY_FILE" ]]; then
  run_one "$QUERY_FILE"
else
  shopt -s nullglob
  for sql_file in "$QUERY_DIR"/*.sql; do
    run_one "$sql_file"
  done
  shopt -u nullglob
fi

printf 'wrote %s\n' "$SUMMARY_FILE"
