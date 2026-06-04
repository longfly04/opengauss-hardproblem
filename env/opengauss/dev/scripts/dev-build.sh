#!/usr/bin/env bash
set -euo pipefail

BUILD_ROOT="/workspace/opengauss-build"
SOURCE_DIR="/workspace/openGauss-server"
BINARYLIBS_DIR="/workspace/openGauss-third_party"
INSTALL_PREFIX="${OPENGAUSS_INSTALL_PREFIX:-/opt/opengauss/install}"
BUILD_TYPE="${OPENGAUSS_BUILD_TYPE:-debug}"
BUILD_OUTPUT_DIR="$SOURCE_DIR/mppdb_temp_install"

required_binarylibs_root_paths=(
  "buildtools"
  "kernel/platform"
  "kernel/dependency"
)
required_binarylibs_diagnostic_paths=(
  "kernel/dependency/llvm/comm/bin/llvm-config"
  "kernel/dependency/cjson/comm/include/cjson/cJSON.h"
  "kernel/dependency/kerberos/comm/include"
  "kernel/dependency/libcgroup/comm/include/libcgroup.h"
  "kernel/dependency/zstd/include/zstd.h"
)

mkdir -p "$BUILD_ROOT" "$INSTALL_PREFIX"
cd "$SOURCE_DIR"

if [[ ! -x ./build.sh ]]; then
  echo "build.sh not found in $SOURCE_DIR" >&2
  exit 1
fi

printf 'source root: %s\n' "$SOURCE_DIR"
printf 'binarylibs root: %s\n' "$BINARYLIBS_DIR"
printf 'build type: %s\n' "$BUILD_TYPE"
printf 'build output dir: %s\n' "$BUILD_OUTPUT_DIR"

CCACHE_SHIM_DIR="$BUILD_ROOT/no-ccache/bin"
mkdir -p "$CCACHE_SHIM_DIR"
cat > "$CCACHE_SHIM_DIR/ccache" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$CCACHE_SHIM_DIR/ccache"
export PATH="$CCACHE_SHIM_DIR:$PATH"

missing_binarylibs_paths=()
for relative_path in "${required_binarylibs_root_paths[@]}"; do
  if [[ ! -e "$BINARYLIBS_DIR/$relative_path" ]]; then
    missing_binarylibs_paths+=("$relative_path")
  fi
done
for relative_path in "${required_binarylibs_diagnostic_paths[@]}"; do
  if [[ ! -e "$BINARYLIBS_DIR/$relative_path" ]]; then
    missing_binarylibs_paths+=("$relative_path")
  fi
done

if (( ${#missing_binarylibs_paths[@]} > 0 )); then
  printf 'binarylibs root is invalid or incomplete: %s\n' "$BINARYLIBS_DIR" >&2
  printf 'missing required path: %s\n' "${missing_binarylibs_paths[@]}" >&2
  exit 1
fi

./build.sh -m "$BUILD_TYPE" -3rd "$BINARYLIBS_DIR"

if [[ ! -x "$BUILD_OUTPUT_DIR/bin/gaussdb" ]]; then
  echo "compiled install tree is missing gaussdb under $BUILD_OUTPUT_DIR" >&2
  exit 1
fi

rsync -a --delete "$BUILD_OUTPUT_DIR/" "$INSTALL_PREFIX/"

if [[ ! -x "$INSTALL_PREFIX/bin/gaussdb" ]]; then
  echo "staged install tree is missing gaussdb under $INSTALL_PREFIX" >&2
  exit 1
fi
