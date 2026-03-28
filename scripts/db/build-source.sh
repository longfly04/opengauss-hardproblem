#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ensure_cmd docker
ensure_env_file
export OPENGAUSS_RUNTIME_MODE=source

if [[ ! -d "$REPO_ROOT/${OPENGAUSS_SOURCE_DIR#./}" ]]; then
  fail "openGauss source directory not found: $REPO_ROOT/${OPENGAUSS_SOURCE_DIR#./}"
fi

if [[ ! -d "$REPO_ROOT/${OPENGAUSS_THIRD_PARTY_DIR#./}" ]]; then
  fail "openGauss third_party directory not found: $REPO_ROOT/${OPENGAUSS_THIRD_PARTY_DIR#./}"
fi

log "building openGauss source development image"
compose build opengauss-dev
log "compiling openGauss source inside dev container"
compose run --rm opengauss-dev bash -lc "dev-build.sh"
log "building openGauss source runtime image"
compose build opengauss
