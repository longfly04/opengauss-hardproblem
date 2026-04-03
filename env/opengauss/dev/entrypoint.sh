#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
INSTALL_PREFIX="${OPENGAUSS_INSTALL_PREFIX:-/opt/opengauss/install}"
DATA_DIR="${OPENGAUSS_DATA_DIR:-/var/lib/opengauss}"
LOG_DIR="${OPENGAUSS_LOG_DIR:-/var/log/opengauss}"
NODE_NAME="${OPENGAUSS_NODE_NAME:-single_node}"
DB_CONTAINER_USER="${DB_CONTAINER_USER:-omm}"
DB_ADMIN_USER="${DB_ADMIN_USER:-gaussdb}"
GS_PASSWORD="${GS_PASSWORD:-ChangeMe_123}"

mkdir -p "$DATA_DIR" "$LOG_DIR"
chown -R "$DB_CONTAINER_USER:$DB_CONTAINER_USER" "$DATA_DIR" "$LOG_DIR"
export PATH="$INSTALL_PREFIX/bin:$PATH"

init_cluster() {
  if [[ ! -f "$DATA_DIR/postgresql.conf" ]]; then
    pwfile="$(mktemp)"
    printf '%s\n' "$GS_PASSWORD" > "$pwfile"
    chown "$DB_CONTAINER_USER:$DB_CONTAINER_USER" "$pwfile"
    gosu "$DB_CONTAINER_USER" gs_initdb -D "$DATA_DIR" --nodename="$NODE_NAME" --pwfile="$pwfile"
    rm -f "$pwfile"
  fi
}

start_db() {
  gosu "$DB_CONTAINER_USER" gs_ctl start -D "$DATA_DIR" -Z single_node -l "$LOG_DIR/opengauss.log"
}

wait_db() {
  local retries=60
  local i
  for ((i = 1; i <= retries; i++)); do
    if gosu "$DB_CONTAINER_USER" gsql -d postgres -Atqc "select 1" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

ensure_admin_user() {
  gosu "$DB_CONTAINER_USER" gsql -d postgres -v ON_ERROR_STOP=1 -Atqc "DO \\\$\\\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$DB_ADMIN_USER') THEN EXECUTE format('CREATE USER %I SYSADMIN PASSWORD %L', '$DB_ADMIN_USER', '$GS_PASSWORD'); END IF; END \\\$\\\$;"
}

init_cluster

case "$MODE" in
  run)
    start_db
    wait_db
    ensure_admin_user
    tail -F "$LOG_DIR/opengauss.log"
    ;;
  debug)
    gosu "$DB_CONTAINER_USER" gdbserver 0.0.0.0:52345 "$INSTALL_PREFIX/bin/gaussdb" -D "$DATA_DIR" -Z single_node
    ;;
  shell)
    exec gosu "$DB_CONTAINER_USER" bash
    ;;
  *)
    exec "$@"
    ;;
esac
