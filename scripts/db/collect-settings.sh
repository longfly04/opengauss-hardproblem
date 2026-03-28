#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

OUTPUT_FILE="${1:-$REPO_ROOT/experiments/reports/current-settings.tsv}"
mkdir -p "$(dirname -- "$OUTPUT_FILE")"

ensure_env_file
compose exec -T -u omm opengauss gsql -v ON_ERROR_STOP=1 -d "$DB_NAME" -Atqc "select name || E'\\t' || setting || E'\\t' || unit from pg_settings order by name" > "$OUTPUT_FILE"

printf 'wrote %s\n' "$OUTPUT_FILE"
