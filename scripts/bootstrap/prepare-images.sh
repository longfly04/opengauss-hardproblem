#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

INCLUDE_DB_SOURCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-db-source)
      INCLUDE_DB_SOURCE=1
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

ensure_cmd docker
ensure_env_file

log "building custom images"
compose build og-memory-exporter tpcc-runner tpch-tools

if [[ "$INCLUDE_DB_SOURCE" -eq 1 || "$OPENGAUSS_RUNTIME_MODE" == "source" ]]; then
  "$REPO_ROOT/scripts/db/build-source.sh"
fi
