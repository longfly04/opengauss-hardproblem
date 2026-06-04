#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

SCALE_FACTOR=1
GENERATE_ONLY=0
DATA_POLICY="force_reload"
SEED_NAME=""
LEGACY_DATA_DIR="$REPO_ROOT/benchmarks/tpch/generated/data"
SEED_ROOT_DIR="$REPO_ROOT/benchmarks/tpch/generated"
DATA_DIR=""
MANIFEST_FILE=""
TABLE_LIST=(region nation supplier customer part partsupp orders lineitem)
SCHEMA_FILE="$REPO_ROOT/benchmarks/tpch/schema.sql"

usage() {
  cat <<'EOF'
Usage: load-tpch.sh [options]
  --scale-factor <n>
  --generate-only
  --data-dir <path>
  --data-policy <force_reload|reuse_if_present|seed_once>
  --seed-name <name>
EOF
}

resolve_paths() {
  if [[ -n "$DATA_DIR" ]]; then
    DATA_DIR="$(realpath -m "$DATA_DIR")"
    if [[ -n "$SEED_NAME" ]]; then
      MANIFEST_FILE="$(dirname "$DATA_DIR")/manifest.env"
    else
      MANIFEST_FILE="$SEED_ROOT_DIR/manifest.env"
    fi
    return
  fi

  if [[ -n "$SEED_NAME" ]]; then
    DATA_DIR="$SEED_ROOT_DIR/$SEED_NAME/data"
    MANIFEST_FILE="$SEED_ROOT_DIR/$SEED_NAME/manifest.env"
  else
    DATA_DIR="$LEGACY_DATA_DIR"
    MANIFEST_FILE="$SEED_ROOT_DIR/manifest.env"
  fi
}

schema_checksum() {
  sha256sum "$SCHEMA_FILE" | awk '{print $1}'
}

have_flat_files() {
  local table_name
  for table_name in "${TABLE_LIST[@]}"; do
    [[ -f "$DATA_DIR/${table_name}.csv" ]] || return 1
  done
}

manifest_matches() {
  [[ -f "$MANIFEST_FILE" ]] || return 1

  local manifest_scale_factor=""
  local manifest_schema_checksum=""
  local manifest_seed_name=""
  # shellcheck disable=SC1090
  source "$MANIFEST_FILE"
  manifest_scale_factor="${tpch_scale_factor:-}"
  manifest_schema_checksum="${schema_checksum:-}"
  manifest_seed_name="${tpch_seed_name:-}"

  [[ "$manifest_scale_factor" == "$SCALE_FACTOR" ]] || return 1
  [[ "$manifest_schema_checksum" == "$(schema_checksum)" ]] || return 1
  if [[ -n "$SEED_NAME" ]]; then
    [[ "$manifest_seed_name" == "$SEED_NAME" ]] || return 1
  fi
}

write_manifest() {
  mkdir -p "$(dirname -- "$MANIFEST_FILE")"
  cat > "$MANIFEST_FILE" <<EOF
seed_name=${SEED_NAME:-legacy}
tpch_seed_name=${SEED_NAME:-legacy}
tpch_scale_factor=$SCALE_FACTOR
schema_checksum=$(schema_checksum)
data_dir=${DATA_DIR#"$REPO_ROOT/"}
generated_at=$(date --iso-8601=seconds)
EOF
}

db_has_tpch_seed() {
  local sql="SELECT CASE
    WHEN NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'region'
    ) THEN 0
    WHEN NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'nation'
    ) THEN 0
    WHEN NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'supplier'
    ) THEN 0
    WHEN NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'customer'
    ) THEN 0
    WHEN NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'part'
    ) THEN 0
    WHEN NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'partsupp'
    ) THEN 0
    WHEN NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'orders'
    ) THEN 0
    WHEN NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'lineitem'
    ) THEN 0
    WHEN EXISTS (SELECT 1 FROM region LIMIT 1)
     AND EXISTS (SELECT 1 FROM nation LIMIT 1)
     AND EXISTS (SELECT 1 FROM supplier LIMIT 1)
     AND EXISTS (SELECT 1 FROM customer LIMIT 1)
     AND EXISTS (SELECT 1 FROM part LIMIT 1)
     AND EXISTS (SELECT 1 FROM partsupp LIMIT 1)
     AND EXISTS (SELECT 1 FROM orders LIMIT 1)
     AND EXISTS (SELECT 1 FROM lineitem LIMIT 1)
    THEN 1 ELSE 0 END;"
  [[ "$(run_gsql "$DB_NAME" "$sql")" == "1" ]]
}

generate_flat_files() {
  ensure_cmd docker
  ensure_env_file
  compose build tpch-tools
  mkdir -p "$DATA_DIR"

  log "generating TPCH data at scale factor $SCALE_FACTOR into $DATA_DIR"
  local tmp_script
  tmp_script="$(mktemp)"
  cat > "$tmp_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd /opt/tpch-kit/dbgen
./dbgen -vf -s "$SCALE_FACTOR"
mkdir -p "/workspace/${DATA_DIR#"$REPO_ROOT/"}"
for tbl in *.tbl; do
  if [[ -f "\$tbl" ]]; then
    sed 's/|$//' "\$tbl" > "/workspace/${DATA_DIR#"$REPO_ROOT/"}/\${tbl%.tbl}.csv"
  fi
done
EOF
  chmod +x "$tmp_script"
  compose run --rm --no-deps -v "$tmp_script:/tmp/generate-tpch.sh" --entrypoint="bash" tpch-tools -c "/tmp/generate-tpch.sh"
  rm -f "$tmp_script"
  write_manifest
}

load_tpch_into_db() {
  wait_for_db
  run_gsql "$DB_NAME" "DROP TABLE IF EXISTS lineitem CASCADE; DROP TABLE IF EXISTS orders CASCADE; DROP TABLE IF EXISTS partsupp CASCADE; DROP TABLE IF EXISTS part CASCADE; DROP TABLE IF EXISTS supplier CASCADE; DROP TABLE IF EXISTS customer CASCADE; DROP TABLE IF EXISTS nation CASCADE; DROP TABLE IF EXISTS region CASCADE;"
  run_gsql_file "$DB_NAME" /workspace/benchmarks/tpch/schema.sql

  local table_name
  for table_name in "${TABLE_LIST[@]}"; do
    log "loading TPCH table: $table_name"
    run_gsql "$DB_NAME" "\\copy $table_name from '/workspace/${DATA_DIR#"$REPO_ROOT/"}/${table_name}.csv' with (format csv, delimiter '|')"
  done
}

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
    --data-policy)
      DATA_POLICY="$2"
      shift
      ;;
    --seed-name)
      SEED_NAME="$2"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

case "$DATA_POLICY" in
  force_reload|reuse_if_present|seed_once)
    ;;
  *)
    fail "unsupported TPCH data policy: $DATA_POLICY"
    ;;
esac

resolve_paths

if [[ "$DATA_POLICY" != "force_reload" ]] && have_flat_files && manifest_matches; then
  if [[ "$GENERATE_ONLY" -eq 1 ]]; then
    log "reusing existing TPCH flat files from $DATA_DIR"
    exit 0
  fi

  wait_for_db
  if db_has_tpch_seed; then
    log "reusing existing TPCH seed from database and flat files at $DATA_DIR"
    exit 0
  fi

  log "reusing existing TPCH flat files from $DATA_DIR and loading into database"
  load_tpch_into_db
  log "TPCH data load complete"
  exit 0
fi

generate_flat_files

if [[ "$GENERATE_ONLY" -eq 1 ]]; then
  log "generated TPCH flat files only"
  exit 0
fi

load_tpch_into_db
log "TPCH data load complete"
