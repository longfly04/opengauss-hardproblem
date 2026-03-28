#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  printf 'usage: %s <sql-file-under-repo> [database] [--mode stock|source]\n' "$0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

SQL_FILE="$1"
shift
DATABASE="${1:-}"
if [[ -n "$DATABASE" && "$DATABASE" != --* ]]; then
  shift
else
  DATABASE=""
fi
DATABASE="${DATABASE:-$DB_NAME}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      export OPENGAUSS_RUNTIME_MODE="$2"
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

ensure_env_file
run_gsql_file "$DATABASE" "/opt/opengauss/$SQL_FILE"
