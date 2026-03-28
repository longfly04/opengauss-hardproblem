#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/env/compose/docker-compose.yml"
OBS_COMPOSE_FILE="$REPO_ROOT/env/compose/docker-compose.observability.yml"
ENV_FILE="$REPO_ROOT/env/compose/.env"
ENV_EXAMPLE_FILE="$REPO_ROOT/env/compose/.env.example"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

ensure_env_file() {
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
    log "created default env file at $ENV_FILE"
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

compose() {
  ensure_env_file
  if docker compose version >/dev/null 2>&1; then
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  else
    fail "docker compose plugin or docker-compose is required"
  fi
}

compose_obs() {
  ensure_env_file
  if docker compose version >/dev/null 2>&1; then
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -f "$OBS_COMPOSE_FILE" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -f "$OBS_COMPOSE_FILE" "$@"
  else
    fail "docker compose plugin or docker-compose is required"
  fi
}

wait_for_db() {
  ensure_env_file
  local retries="${1:-60}"
  local sleep_seconds="${2:-5}"
  local i

  for ((i = 1; i <= retries; i++)); do
    if compose exec -T -u omm opengauss gsql -d postgres -Atqc "select 1" >/dev/null 2>&1; then
      log "openGauss is ready"
      return 0
    fi
    log "waiting for openGauss ($i/$retries)"
    sleep "$sleep_seconds"
  done

  fail "openGauss did not become ready in time"
}

run_gsql() {
  ensure_env_file
  local database="$1"
  local sql="$2"
  compose exec -T -u omm opengauss gsql -v ON_ERROR_STOP=1 -d "$database" -Atqc "$sql"
}

run_gsql_file() {
  ensure_env_file
  local database="$1"
  local file_path="$2"
  compose exec -T -u omm opengauss gsql -v ON_ERROR_STOP=1 -d "$database" -f "$file_path"
}

load_flat_yaml() {
  local file_path="$1"
  [[ -f "$file_path" ]] || fail "config file not found: $file_path"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *:* ]] && continue

    local key="${line%%:*}"
    local value="${line#*:}"
    key="$(printf '%s' "$key" | tr '[:lower:]-' '[:upper:]_')"
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//')"

    export "$key=$value"
  done < "$file_path"
}

new_run_dir() {
  local scenario_name="$1"
  local run_id="$(date '+%Y%m%d-%H%M%S')-${scenario_name}"
  local run_dir="$REPO_ROOT/experiments/runs/$run_id"
  mkdir -p "$run_dir"
  printf '%s\n' "$run_dir"
}

copy_if_missing() {
  local source_file="$1"
  local target_file="$2"
  if [[ ! -f "$target_file" ]]; then
    cp "$source_file" "$target_file"
  fi
}
