#!/usr/bin/env bash
set -euo pipefail

BUILD_ROOT="/workspace/opengauss-build"
SOURCE_DIR="/workspace/openGauss-server"
THIRD_PARTY_DIR="/workspace/openGauss-third_party"
INSTALL_PREFIX="${OPENGAUSS_INSTALL_PREFIX:-/opt/opengauss/install}"
BUILD_TYPE="${OPENGAUSS_BUILD_TYPE:-debug}"

mkdir -p "$BUILD_ROOT" "$INSTALL_PREFIX"
cd "$SOURCE_DIR"

if [[ -x ./build.sh ]]; then
  ./build.sh -m "$BUILD_TYPE" -3rd "$THIRD_PARTY_DIR" --prefix="$INSTALL_PREFIX"
else
  echo "build.sh not found in $SOURCE_DIR" >&2
  exit 1
fi
