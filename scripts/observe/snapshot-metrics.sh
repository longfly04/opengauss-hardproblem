#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

OUTPUT_DIR=""
PROM_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift
      ;;
    --prom-url)
      PROM_URL="$2"
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

[[ -n "$OUTPUT_DIR" ]] || fail "--output-dir is required"
PROM_URL="${PROM_URL:-http://localhost:${PROMETHEUS_PORT}}"
mkdir -p "$OUTPUT_DIR"

queries=(
  "sum(opengauss_shared_context_used_bytes)"
  "sum(opengauss_shared_context_total_bytes)"
  "sum(opengauss_session_used_bytes)"
  "max(opengauss_session_used_bytes)"
  "sum(opengauss_temp_bytes_total)"
  "sum(opengauss_activity_sessions{state=~\"active|fastpath function call\"})"
)

index=1
for query in "${queries[@]}"; do
  file="$OUTPUT_DIR/query-$index.json"
  curl -sS --get "$PROM_URL/api/v1/query" --data-urlencode "query=$query" > "$file" || true
  printf '%s\n' "$query" > "$OUTPUT_DIR/query-$index.expr"
  index=$((index + 1))
done
