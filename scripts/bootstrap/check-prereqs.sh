#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
ensure_env_file

missing=0
for cmd in bash sed awk grep date; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    missing=1
  fi
done

if ! command -v docker >/dev/null 2>&1; then
  printf 'missing required command: docker\n' >&2
  missing=1
fi

if command -v docker >/dev/null 2>&1; then
  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    printf 'missing docker compose plugin or docker-compose binary\n' >&2
    missing=1
  fi
fi

for optional in git curl python3 python java mvn gdb gdbserver ccache; do
  if ! command -v "$optional" >/dev/null 2>&1; then
    printf 'optional command not found: %s\n' "$optional"
  fi
done

printf 'repo root: %s\n' "$REPO_ROOT"
printf 'compose env template: %s\n' "$REPO_ROOT/env/compose/.env.example"
printf 'docker-first mode: enabled\n'
printf 'runtime mode: %s\n' "${OPENGAUSS_RUNTIME_MODE:-stock}"
printf 'db service: %s\n' "${DB_SERVICE_NAME:-opengauss}"
printf 'db endpoint: %s:%s\n' "${DB_HOST:-opengauss}" "${DB_PORT:-5432}"
printf 'source build baseline: %s\n' "$OPENGAUSS_SOURCE_BUILD_BASELINE"

if [[ -n "${OPENGAUSS_SOURCE_DIR:-}" || -n "${OPENGAUSS_BINARYLIBS_DIR:-}" || -n "${OPENGAUSS_THIRD_PARTY_DIR:-}" || "${OPENGAUSS_RUNTIME_MODE:-stock}" == "source" ]]; then
  source_dir="$(get_opengauss_source_dir)"
  binarylibs_dir="$(get_opengauss_binarylibs_dir)"
  printf 'source dir: %s\n' "$source_dir"
  printf 'binarylibs dir: %s\n' "$binarylibs_dir"
  printf 'binarylibs root expectations: %s\n' 'buildtools/, kernel/platform/, kernel/dependency/'

  if ! validate_opengauss_source_root "$source_dir"; then
    missing=1
  fi

  if ! validate_opengauss_binarylibs_root "$binarylibs_dir"; then
    missing=1
  fi
fi

exit "$missing"
