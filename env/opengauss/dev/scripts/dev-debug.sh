#!/usr/bin/env bash
set -euo pipefail

INSTALL_PREFIX="${OPENGAUSS_INSTALL_PREFIX:-/opt/opengauss/install}"
DATA_DIR="${OPENGAUSS_DATA_DIR:-/var/lib/opengauss}"
export PATH="$INSTALL_PREFIX/bin:$PATH"
exec gdbserver 0.0.0.0:52345 "$INSTALL_PREFIX/bin/gaussdb" -D "$DATA_DIR" -Z single_node
