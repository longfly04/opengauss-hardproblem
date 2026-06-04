#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
INSTALL_PREFIX="${OPENGAUSS_INSTALL_PREFIX:-/opt/opengauss/install}"
DATA_ROOT="${OPENGAUSS_DATA_DIR:-/var/lib/opengauss}"
LOG_DIR="${OPENGAUSS_LOG_DIR:-/var/log/opengauss}"
NODE_NAME="${OPENGAUSS_NODE_NAME:-single_node}"
DB_CONTAINER_USER="${DB_CONTAINER_USER:-omm}"
DB_ADMIN_USER="${DB_ADMIN_USER:-gaussdb}"
GS_PASSWORD="${GS_PASSWORD:-ChangeMe_123}"

resolve_cluster_dir() {
  if [[ -f "$DATA_ROOT/postgresql.conf" || -d "$DATA_ROOT/base" ]]; then
    printf '%s\n' "$DATA_ROOT"
    return
  fi

  if [[ -f "$DATA_ROOT/data/postgresql.conf" || -d "$DATA_ROOT/data/base" || -d "$DATA_ROOT/data" ]]; then
    printf '%s\n' "$DATA_ROOT/data"
    return
  fi

  printf '%s\n' "$DATA_ROOT/data"
}

DATA_DIR="$(resolve_cluster_dir)"
mkdir -p "$DATA_ROOT" "$DATA_DIR" "$LOG_DIR"
chown -R "$DB_CONTAINER_USER:$DB_CONTAINER_USER" "$DATA_ROOT" "$LOG_DIR"
export GAUSSHOME="$INSTALL_PREFIX"
export LANG="${LANG:-C.utf8}"
export LC_ALL="${LC_ALL:-C.utf8}"
export PATH="/usr/local/bin:$INSTALL_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$INSTALL_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

normalize_cluster_locale_config() {
  local config_file="$DATA_DIR/postgresql.conf"

  [[ -f "$config_file" ]] || return 0

  if locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -qx 'en_us.utf8'; then
    return 0
  fi

  python3 - "$config_file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
replacements = {
    "lc_messages = 'en_US.utf8'": "lc_messages = 'C.utf8'",
    "lc_monetary = 'en_US.utf8'": "lc_monetary = 'C.utf8'",
    "lc_numeric = 'en_US.utf8'": "lc_numeric = 'C.utf8'",
    "lc_time = 'en_US.utf8'": "lc_time = 'C.utf8'",
    "lc_messages = 'en_US.UTF-8'": "lc_messages = 'C.utf8'",
    "lc_monetary = 'en_US.UTF-8'": "lc_monetary = 'C.utf8'",
    "lc_numeric = 'en_US.UTF-8'": "lc_numeric = 'C.utf8'",
    "lc_time = 'en_US.UTF-8'": "lc_time = 'C.utf8'",
}
updated = text
for old, new in replacements.items():
    updated = updated.replace(old, new)
if updated != text:
    path.write_text(updated)
PY
}

run_as_db_user() {
  runuser -u "$DB_CONTAINER_USER" -- env PATH="$PATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" GAUSSHOME="$GAUSSHOME" LANG="$LANG" LC_ALL="$LC_ALL" "$@"
}

init_cluster() {
  if [[ ! -f "$DATA_DIR/postgresql.conf" ]]; then
    pwfile="$(mktemp)"
    printf '%s\n' "$GS_PASSWORD" > "$pwfile"
    chown "$DB_CONTAINER_USER:$DB_CONTAINER_USER" "$pwfile"
    run_as_db_user gs_initdb -D "$DATA_DIR" --nodename="$NODE_NAME" --pwfile="$pwfile"
    rm -f "$pwfile"
  fi
}

start_db() {
  run_as_db_user gs_ctl start -D "$DATA_DIR" -Z single_node -l "$LOG_DIR/opengauss.log"
}

wait_db() {
  local retries=60
  local i
  for ((i = 1; i <= retries; i++)); do
    if run_as_db_user gsql -d postgres -Atqc "select 1" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

ensure_admin_user() {
  if [[ "$(run_as_db_user gsql -d postgres -Atqc "select count(*) from pg_roles where rolname = '$DB_ADMIN_USER'")" != "0" ]]; then
    return 0
  fi

  local create_user_sql
  create_user_sql="$(python3 - "$DB_ADMIN_USER" "$GS_PASSWORD" <<'PY'
import sys

user = sys.argv[1].replace('"', '""')
password = sys.argv[2].replace("'", "''")
print(f'CREATE USER "{user}" SYSADMIN PASSWORD \'{password}\';')
PY
)"

  run_as_db_user gsql -d postgres -v ON_ERROR_STOP=1 -Atqc "$create_user_sql"
}

init_cluster
normalize_cluster_locale_config

case "$MODE" in
  run)
    start_db
    wait_db
    ensure_admin_user
    tail -F "$LOG_DIR/opengauss.log"
    ;;
  debug)
    exec runuser -u "$DB_CONTAINER_USER" -- env PATH="$PATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" GAUSSHOME="$GAUSSHOME" LANG="$LANG" LC_ALL="$LC_ALL" gdbserver 0.0.0.0:52345 "$INSTALL_PREFIX/bin/gaussdb" -D "$DATA_DIR" -Z single_node
    ;;
  shell)
    exec runuser -u "$DB_CONTAINER_USER" -- env PATH="$PATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" GAUSSHOME="$GAUSSHOME" LANG="$LANG" LC_ALL="$LC_ALL" bash
    ;;
  *)
    exec "$@"
    ;;
esac
