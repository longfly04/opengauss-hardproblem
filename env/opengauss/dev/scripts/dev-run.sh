#!/usr/bin/env bash
set -euo pipefail

INSTALL_PREFIX="${OPENGAUSS_INSTALL_PREFIX:-/opt/opengauss/install}"
DATA_DIR="${OPENGAUSS_DATA_DIR:-/var/lib/opengauss}"
LOG_DIR="${OPENGAUSS_LOG_DIR:-/var/log/opengauss}"
mkdir -p "$DATA_DIR" "$LOG_DIR"
export PATH="$INSTALL_PREFIX/bin:$PATH"
gs_ctl start -D "$DATA_DIR" -Z single_node -l "$LOG_DIR/opengauss.log"
