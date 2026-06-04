#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/env/compose/docker-compose.yml"
STOCK_COMPOSE_FILE="$REPO_ROOT/env/compose/docker-compose.stock.yml"
SOURCE_COMPOSE_FILE="$REPO_ROOT/env/compose/docker-compose.source.yml"
OBS_COMPOSE_FILE="$REPO_ROOT/env/compose/docker-compose.observability.yml"
ENV_FILE="$REPO_ROOT/env/compose/.env"
ENV_EXAMPLE_FILE="$REPO_ROOT/env/compose/.env.example"
OPENGAUSS_SOURCE_BUILD_BASELINE="openEuler 24.03 x86_64"
OPENGAUSS_BINARYLIBS_ARCHIVE_URL="https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/binarylibs/gcc10.3/openGauss-third_party_binarylibs_openEuler_2403_x86_64.tar.gz"

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

migrate_legacy_source_paths() {
  local legacy_source="./openGauss-server"
  local preferred_source="./ThirdParty/openGauss-server"
  local current_source="${OPENGAUSS_SOURCE_DIR:-$legacy_source}"

  if [[ "$current_source" == "$legacy_source" ]] && [[ ! -d "$REPO_ROOT/${legacy_source#./}" ]] && [[ -d "$REPO_ROOT/${preferred_source#./}" ]]; then
    export OPENGAUSS_SOURCE_DIR="$preferred_source"
    log "OPENGAUSS_SOURCE_DIR not found at $legacy_source; using $preferred_source"
  fi

  local legacy_binarylibs="./openGauss-third_party"
  local preferred_binarylibs="./ThirdParty/openGauss-binarylibs"
  local current_binarylibs="${OPENGAUSS_BINARYLIBS_DIR:-${OPENGAUSS_THIRD_PARTY_DIR:-$legacy_binarylibs}}"

  if [[ "$current_binarylibs" == "$legacy_binarylibs" ]] && [[ ! -d "$REPO_ROOT/${legacy_binarylibs#./}" ]] && [[ -d "$REPO_ROOT/${preferred_binarylibs#./}" ]]; then
    export OPENGAUSS_BINARYLIBS_DIR="$preferred_binarylibs"
    log "binarylibs dir not found at $legacy_binarylibs; using $preferred_binarylibs"
  elif [[ -z "${OPENGAUSS_BINARYLIBS_DIR:-}" ]] && [[ -n "${OPENGAUSS_THIRD_PARTY_DIR:-}" ]]; then
    export OPENGAUSS_BINARYLIBS_DIR="$OPENGAUSS_THIRD_PARTY_DIR"
  fi

  if [[ -n "${OPENGAUSS_SOURCE_DIR:-}" ]] && [[ "$OPENGAUSS_SOURCE_DIR" != /* ]]; then
    export OPENGAUSS_SOURCE_DIR="$REPO_ROOT/${OPENGAUSS_SOURCE_DIR#./}"
  fi

  if [[ -n "${OPENGAUSS_BINARYLIBS_DIR:-}" ]] && [[ "$OPENGAUSS_BINARYLIBS_DIR" != /* ]]; then
    export OPENGAUSS_BINARYLIBS_DIR="$REPO_ROOT/${OPENGAUSS_BINARYLIBS_DIR#./}"
  fi

  local legacy_client_bin="/usr/local/opengauss/bin/gsql"
  local preferred_client_bin="/usr/local/bin/gsql"
  if [[ "${DB_CLIENT_BIN:-}" == "$legacy_client_bin" ]]; then
    export DB_CLIENT_BIN="$preferred_client_bin"
    log "DB_CLIENT_BIN points to legacy runtime path $legacy_client_bin; using $preferred_client_bin"
  fi

  local preferred_stock_image="local/opengauss-stock-baseline:latest"
  case "${OPENGAUSS_IMAGE:-$preferred_stock_image}" in
    opengauss/opengauss-server:latest|docker.1ms.run/opengauss/opengauss-server:latest)
      export OPENGAUSS_IMAGE="$preferred_stock_image"
      log "OPENGAUSS_IMAGE points to legacy stock image; using $preferred_stock_image"
      ;;
  esac
}

resolve_repo_path() {
  local path="$1"

  if [[ -z "$path" ]]; then
    return 1
  fi

  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$REPO_ROOT/${path#./}"
  fi
}

get_opengauss_source_dir() {
  resolve_repo_path "${OPENGAUSS_SOURCE_DIR:-./ThirdParty/openGauss-server}"
}

get_opengauss_binarylibs_dir() {
  resolve_repo_path "${OPENGAUSS_BINARYLIBS_DIR:-${OPENGAUSS_THIRD_PARTY_DIR:-./ThirdParty/openGauss-binarylibs}}"
}

validate_opengauss_source_root() {
  local source_dir="$1"
  local missing=0

  if [[ ! -L "$source_dir" && ! -d "$source_dir" ]]; then
    printf 'openGauss source directory does not exist: %s\n' "$source_dir" >&2
    return 1
  fi

  if [[ ! -f "$source_dir/build.sh" ]]; then
    printf 'openGauss source directory is invalid (missing build.sh): %s\n' "$source_dir" >&2
    missing=1
  fi

  return "$missing"
}

validate_opengauss_binarylibs_root() {
  local binarylibs_dir="$1"
  local missing=0
  local required_root_paths=(
    "buildtools"
    "kernel/platform"
    "kernel/dependency"
  )
  local diagnostic_paths=(
    "kernel/dependency/llvm/comm/bin/llvm-config"
    "kernel/dependency/cjson/comm/include/cjson/cJSON.h"
    "kernel/dependency/kerberos/comm/include"
    "kernel/dependency/libcgroup/comm/include/libcgroup.h"
    "kernel/dependency/zstd/include/zstd.h"
  )

  if [[ ! -L "$binarylibs_dir" && ! -d "$binarylibs_dir" ]]; then
    printf 'openGauss binarylibs directory does not exist: %s\n' "$binarylibs_dir" >&2
    return 1
  fi

  for relative_path in "${required_root_paths[@]}"; do
    if [[ ! -e "$binarylibs_dir/$relative_path" ]]; then
      printf 'binarylibs root is invalid, missing required path: %s\n' "$relative_path" >&2
      missing=1
    fi
  done

  for relative_path in "${diagnostic_paths[@]}"; do
    if [[ ! -e "$binarylibs_dir/$relative_path" ]]; then
      printf 'binarylibs appears incomplete, missing diagnostic path: %s\n' "$relative_path" >&2
      missing=1
    fi
  done

  if [[ "$missing" -ne 0 ]]; then
    printf 'expected extracted binarylibs root from %s\n' "$OPENGAUSS_BINARYLIBS_ARCHIVE_URL" >&2
  fi

  return "$missing"
}

ensure_env_file() {
  local runtime_mode_override="${OPENGAUSS_RUNTIME_MODE:-}"

  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
    log "created default env file at $ENV_FILE"
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  if [[ -n "$runtime_mode_override" ]]; then
    export OPENGAUSS_RUNTIME_MODE="$runtime_mode_override"
  fi

  migrate_legacy_source_paths
}

compose_files() {
  ensure_env_file
  local files=("-f" "$COMPOSE_FILE")
  if [[ "${OPENGAUSS_RUNTIME_MODE:-stock}" == "source" ]]; then
    files+=("-f" "$SOURCE_COMPOSE_FILE")
  else
    files+=("-f" "$STOCK_COMPOSE_FILE")
  fi
  printf '%s\n' "${files[@]}"
}

compose() {
  ensure_env_file
  mapfile -t files < <(compose_files)
  if docker compose version >/dev/null 2>&1; then
    docker compose --env-file "$ENV_FILE" "${files[@]}" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose --env-file "$ENV_FILE" "${files[@]}" "$@"
  else
    fail "docker compose plugin or docker-compose is required"
  fi
}

compose_obs() {
  ensure_env_file
  mapfile -t files < <(compose_files)
  files+=("-f" "$OBS_COMPOSE_FILE")
  if docker compose version >/dev/null 2>&1; then
    docker compose --env-file "$ENV_FILE" "${files[@]}" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose --env-file "$ENV_FILE" "${files[@]}" "$@"
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
    if compose exec -T -u "$DB_CONTAINER_USER" "$DB_SERVICE_NAME" "$DB_CLIENT_BIN" -d postgres -Atqc "select 1" >/dev/null 2>&1; then
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
  compose exec -T -u "$DB_CONTAINER_USER" "$DB_SERVICE_NAME" "$DB_CLIENT_BIN" -v ON_ERROR_STOP=1 -d "$database" -Atqc "$sql"
}

run_gsql_file() {
  ensure_env_file
  local database="$1"
  local file_path="$2"
  compose exec -T -u "$DB_CONTAINER_USER" "$DB_SERVICE_NAME" "$DB_CLIENT_BIN" -v ON_ERROR_STOP=1 -d "$database" -f "$file_path"
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
