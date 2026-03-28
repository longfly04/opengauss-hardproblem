#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

FULL_OBSERVABILITY=0
SKIP_INIT=0
APPLY_SQL_FILE=""
RUNTIME_MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full-observability)
      FULL_OBSERVABILITY=1
      ;;
    --skip-init)
      SKIP_INIT=1
      ;;
    --apply-sql)
      APPLY_SQL_FILE="$2"
      shift
      ;;
    --mode)
      RUNTIME_MODE="$2"
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

if [[ -n "$RUNTIME_MODE" ]]; then
  export OPENGAUSS_RUNTIME_MODE="$RUNTIME_MODE"
fi

if [[ "$OPENGAUSS_RUNTIME_MODE" == "source" ]]; then
  "$REPO_ROOT/scripts/db/build-source.sh"
fi

if [[ "$FULL_OBSERVABILITY" -eq 1 ]]; then
  log "starting openGauss lab with host observability"
  compose_obs up -d
else
  log "starting openGauss lab"
  compose up -d
fi

wait_for_db

if [[ "$SKIP_INIT" -eq 0 ]]; then
  log "applying bootstrap SQL"
  run_gsql_file postgres /opt/opengauss/bootstrap/00-create-users.sql
  if [[ "$(run_gsql postgres "select count(*) from pg_database where datname = '$DB_NAME'")" == "0" ]]; then
    run_gsql postgres "create database \"$DB_NAME\" owner \"$BENCH_USER\""
  fi
  run_gsql_file postgres /opt/opengauss/bootstrap/02-enable-stats.sql
  run_gsql_file "$DB_NAME" /opt/opengauss/sql/observability/install_views.sql
  run_gsql_file "$DB_NAME" /opt/opengauss/sql/tuning/baseline_params.sql
fi

if [[ -n "$APPLY_SQL_FILE" ]]; then
  log "applying additional SQL preset: $APPLY_SQL_FILE"
  run_gsql_file "$DB_NAME" "/opt/opengauss/$APPLY_SQL_FILE"
fi

log "openGauss lab is ready"
log "runtime mode: ${OPENGAUSS_RUNTIME_MODE}"
log "grafana: http://localhost:${GRAFANA_PORT}"
log "prometheus: http://localhost:${PROMETHEUS_PORT}"
