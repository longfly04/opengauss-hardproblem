#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

RUNTIME_MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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

log "resetting openGauss volumes"
compose_obs down --volumes --remove-orphans || true
rm -rf "$REPO_ROOT/experiments/runs"/* "$REPO_ROOT/experiments/reports"/*
mkdir -p "$REPO_ROOT/experiments/runs" "$REPO_ROOT/experiments/reports"
log "reset complete"
