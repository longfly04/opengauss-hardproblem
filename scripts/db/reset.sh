#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ensure_cmd docker
ensure_env_file

log "resetting openGauss volumes"
compose_obs down --volumes --remove-orphans || true
rm -rf "$REPO_ROOT/experiments/runs"/* "$REPO_ROOT/experiments/reports"/*
mkdir -p "$REPO_ROOT/experiments/runs" "$REPO_ROOT/experiments/reports"
log "reset complete"
