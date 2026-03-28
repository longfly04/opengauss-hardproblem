#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

SCALE_FACTOR=1
GENERATE_ONLY=0
DATA_DIR="$REPO_ROOT/benchmarks/tpch/generated/data"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scale-factor)
      SCALE_FACTOR="$2"
      shift
      ;;
    --generate-only)
      GENERATE_ONLY=1
      ;;
    --data-dir)
      DATA_DIR="$2"
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

ensure_cmd docker
ensure_env_file
compose build tpch-tools
mkdir -p "$DATA_DIR"

log "generating TPCH data at scale factor $SCALE_FACTOR"
compose run --rm --no-deps tpch-tools bash -lc "cd /opt/tpch-kit/dbgen && ./dbgen -vf -s $SCALE_FACTOR && mkdir -p /workspace/benchmarks/tpch/generated/data && for tbl in *.tbl; do sed 's/|$//' \"$tbl\" > \"/workspace/benchmarks/tpch/generated/data/${tbl%.tbl}.csv\"; done"

if [[ "$GENERATE_ONLY" -eq 1 ]]; then
  log "generated TPCH flat files only"
  exit 0
fi

wait_for_db
run_gsql_file "$DB_NAME" /workspace/benchmarks/tpch/schema.sql

for table_name in region nation supplier customer part partsupp orders lineitem; do
  log "loading TPCH table: $table_name"
  run_gsql "$DB_NAME" "\\copy $table_name from '/workspace/benchmarks/tpch/generated/data/${table_name}.csv' with (format csv, delimiter '|')"
done

log "TPCH data load complete"
