#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

QUERY_DIR="$REPO_ROOT/benchmarks/tpch/variants/spill-prone"
QUERY_FILE=""
OUTPUT_DIR="$REPO_ROOT/experiments/reports/tpch-run"
SUMMARY_FILE="$OUTPUT_DIR/summary.tsv"

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
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

ensure_env_file
mkdir -p "$OUTPUT_DIR"
printf 'query_name\tduration_seconds\tlog_file\tplan_file\n' > "$SUMMARY_FILE"

run_one() {
  local sql_file="$1"
  local query_name="$(basename -- "$sql_file")"
  local relative_path="${sql_file#$REPO_ROOT/}"
  local container_path="/workspace/${relative_path}"
  local log_file="$OUTPUT_DIR/${query_name%.sql}.log"
  local plan_file="$OUTPUT_DIR/${query_name%.sql}.plan"
  local started="$(date +%s)"

  # 收集执行计划
  local sql_content=$(cat "$sql_file")
  compose exec -T -u "$DB_CONTAINER_USER" "$DB_SERVICE_NAME" "$DB_CLIENT_BIN" -v ON_ERROR_STOP=1 -d "$DB_NAME" -c "EXPLAIN ANALYZE $sql_content" > "$plan_file" 2>&1

  # 执行实际查询
  run_gsql_file "$DB_NAME" "$container_path" > "$log_file" 2>&1

  local finished="$(date +%s)"
  printf '%s\t%s\t%s\t%s\n' "$query_name" "$((finished - started))" "$log_file" "$plan_file" >> "$SUMMARY_FILE"
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
