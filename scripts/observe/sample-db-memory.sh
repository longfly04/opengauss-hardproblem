#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

INTERVAL=15
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)
      INTERVAL="$2"
      shift
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

[[ -n "$OUTPUT_FILE" ]] || fail "--output is required"
mkdir -p "$(dirname -- "$OUTPUT_FILE")"
printf 'epoch\tshared_total_bytes\tshared_used_bytes\tshared_free_bytes\tsession_used_sum_bytes\tsession_used_max_bytes\tpeak_session_used_ratio\tactive_sessions\tsession_count\ttemp_bytes\twork_mem_bytes\tquery_mem_bytes\tquery_max_mem_bytes\tmax_process_memory_bytes\n' > "$OUTPUT_FILE"

trap 'exit 0' INT TERM

while true; do
  epoch="$(date +%s)"
  shared_line="$(run_gsql "$DB_NAME" "select coalesce(total_bytes,0) || E'\t' || coalesce(used_bytes,0) || E'\t' || coalesce(free_bytes,0) from lab_obs.shared_memory_totals limit 1" 2>/dev/null || printf '0\t0\t0')"
  session_line="$(run_gsql "$DB_NAME" "select coalesce(sum(used_bytes),0) || E'\t' || coalesce(max(used_bytes),0) || E'\t' || coalesce(max(used_ratio),0) from lab_obs.session_memory_pressure" 2>/dev/null || printf '0\t0\t0')"
  activity_line="$(run_gsql "$DB_NAME" "select coalesce(sum(case when state in ('active', 'fastpath function call') then session_count else 0 end),0) || E'\t' || coalesce(sum(session_count),0) from lab_obs.activity_sessions" 2>/dev/null || printf '0\t0')"
  temp_bytes="$(run_gsql "$DB_NAME" "select coalesce(sum(temp_bytes),0) from lab_obs.database_spill_stats" 2>/dev/null || printf '0')"
  settings_line="$(run_gsql "$DB_NAME" "select coalesce(max(case when name = 'work_mem' then setting_bytes end),0) || E'\t' || coalesce(max(case when name = 'query_mem' then setting_bytes end),0) || E'\t' || coalesce(max(case when name = 'query_max_mem' then setting_bytes end),0) || E'\t' || coalesce(max(case when name = 'max_process_memory' then setting_bytes end),0) from lab_obs.selected_settings" 2>/dev/null || printf '0\t0\t0\t0')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$epoch" "$shared_line" "$session_line" "$activity_line" "$temp_bytes" "$settings_line" >> "$OUTPUT_FILE"
  sleep "$INTERVAL"
done
