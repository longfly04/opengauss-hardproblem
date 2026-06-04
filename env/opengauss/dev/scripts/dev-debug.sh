#!/usr/bin/env bash
set -euo pipefail

INSTALL_PREFIX="${OPENGAUSS_INSTALL_PREFIX:-/opt/opengauss/install}"
DATA_ROOT="${OPENGAUSS_DATA_DIR:-/var/lib/opengauss}"
resolve_cluster_dir() {
  if [[ -f "$DATA_ROOT/postgresql.conf" || -d "$DATA_ROOT/base" ]]; then
    printf '%s\n' "$DATA_ROOT"
    return
  fi

  if [[ -f "$DATA_ROOT/data/postgresql.conf" || -d "$DATA_ROOT/data/base" || -d "$DATA_ROOT/data" ]]; then
    printf '%s\n' "$DATA_ROOT/data"
    return
  fi

  printf '%s\n' "$DATA_ROOT/data"
}
DATA_DIR="$(resolve_cluster_dir)"
export GAUSSHOME="$INSTALL_PREFIX"
export LANG="${LANG:-C.utf8}"
export LC_ALL="${LC_ALL:-C.utf8}"
export PATH="$INSTALL_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$INSTALL_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec gdbserver 0.0.0.0:52345 "$INSTALL_PREFIX/bin/gaussdb" -D "$DATA_DIR" -Z single_node
