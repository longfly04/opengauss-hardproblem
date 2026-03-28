#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

FULL_OBSERVABILITY=0
REMOVE_VOLUMES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full-observability)
      FULL_OBSERVABILITY=1
      ;;
    --volumes)
      REMOVE_VOLUMES=1
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

ensure_cmd docker
ensure_env_file

args=(down)
if [[ "$REMOVE_VOLUMES" -eq 1 ]]; then
  args+=(--volumes)
fi

if [[ "$FULL_OBSERVABILITY" -eq 1 ]]; then
  compose_obs "${args[@]}"
else
  compose "${args[@]}"
fi
