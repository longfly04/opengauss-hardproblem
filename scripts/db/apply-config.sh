#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  printf 'usage: %s <sql-file-under-repo> [database]\n' "$0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

SQL_FILE="$1"
DATABASE="${2:-$DB_NAME}"

ensure_env_file
run_gsql_file "$DATABASE" "/opt/opengauss/$SQL_FILE"
