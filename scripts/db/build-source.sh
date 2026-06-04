#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ensure_cmd docker
ensure_env_file
export OPENGAUSS_RUNTIME_MODE=source

EMIT_STOCK_IMAGE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --emit-stock-image)
      EMIT_STOCK_IMAGE=1
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

STAGING_INSTALL_DIR="$REPO_ROOT/env/opengauss/build-context/install"

stage_install_tree() {
  log "staging compiled openGauss install tree into $STAGING_INSTALL_DIR"
  python3 - "$STAGING_INSTALL_DIR" <<'PY'
import os
import shutil
import sys

path = sys.argv[1]
os.makedirs(path, exist_ok=True)
for name in os.listdir(path):
    target = os.path.join(path, name)
    if os.path.isdir(target) and not os.path.islink(target):
        shutil.rmtree(target)
    else:
        os.unlink(target)
PY

  compose run --rm opengauss-dev bash -lc "test -x '$OPENGAUSS_INSTALL_PREFIX/bin/gaussdb' && tar -C '$OPENGAUSS_INSTALL_PREFIX' -cf - ." \
    | tar -C "$STAGING_INSTALL_DIR" -xf -

  [[ -x "$STAGING_INSTALL_DIR/bin/gaussdb" ]] || fail "staged install tree is missing gaussdb"
}

build_stock_image() {
  log "building trusted openGauss stock baseline image: $OPENGAUSS_IMAGE"
  docker build \
    --file "$REPO_ROOT/env/opengauss/dev/Dockerfile.runtime" \
    --build-arg OPENGAUSS_DEV_IMAGE="$OPENGAUSS_DEV_IMAGE" \
    --build-arg OPENGAUSS_BUILD_TYPE="$OPENGAUSS_BUILD_TYPE" \
    --build-arg OPENGAUSS_INSTALL_PREFIX="$OPENGAUSS_INSTALL_PREFIX" \
    --tag "$OPENGAUSS_IMAGE" \
    "$REPO_ROOT"
}

source_dir="$(get_opengauss_source_dir)"
binarylibs_dir="$(get_opengauss_binarylibs_dir)"

validate_opengauss_source_root "$source_dir" || fail "openGauss source root must contain build.sh: $source_dir"
validate_opengauss_binarylibs_root "$binarylibs_dir" || fail "openGauss binarylibs root must be the extracted upstream bundle (buildtools/, kernel/platform/, kernel/dependency/): $binarylibs_dir"

log "source build baseline: $OPENGAUSS_SOURCE_BUILD_BASELINE"
log "using openGauss source root: $source_dir"
log "using openGauss binarylibs root: $binarylibs_dir"

log "building openGauss source development image"
compose build opengauss-dev
log "compiling openGauss source inside dev container"
compose run --rm opengauss-dev bash -lc "dev-build.sh"
log "building openGauss source runtime image"
compose build opengauss

if [[ "$EMIT_STOCK_IMAGE" -eq 1 ]]; then
  stage_install_tree
  build_stock_image
fi
