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
printf 'epoch\tshared_total_bytes\tshared_used_bytes\tshared_free_bytes\tsession_used_sum_bytes\tsession_used_max_bytes\tactive_sessions\ttemp_bytes\n' > "$OUTPUT_FILE"

trap 'exit 0' INT TERM

while true; do
  epoch="$(date +%s)"
  shared_line="$(run_gsql "$DB_NAME" "select coalesce(total_bytes,0) || E'\t' || coalesce(used_bytes,0) || E'\t' || coalesce(free_bytes,0) from lab_obs.shared_memory_totals limit 1" 2>/dev/null || printf '0\t0\t0')"
  session_line="$(run_gsql "$DB_NAME" "select coalesce(sum(used_bytes),0) || E'\t' || coalesce(max(used_bytes),0) from lab_obs.session_memory_summary" 2>/dev/null || printf '0\t0')"
  active_sessions="$(run_gsql "$DB_NAME" "select coalesce(sum(session_count),0) from lab_obs.activity_sessions where state in ('active', 'fastpath function call')" 2>/dev/null || printf '0')"
  temp_bytes="$(run_gsql "$DB_NAME" "select coalesce(sum(temp_bytes),0) from lab_obs.database_spill_stats" 2>/dev/null || printf '0')"
  printf '%s\t%s\t%s\t%s\n' "$epoch" "$shared_line" "$session_line" "$active_sessions" "$temp_bytes" >> "$OUTPUT_FILE"
  sleep "$INTERVAL"
done
