#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ensure_cmd docker
ensure_env_file
export OPENGAUSS_RUNTIME_MODE=source

"$REPO_ROOT/scripts/db/build-source.sh"
compose run --use-aliases --service-ports --rm opengauss debug
