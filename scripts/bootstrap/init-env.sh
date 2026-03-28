#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

mkdir -p \
  "$REPO_ROOT/experiments/runs" \
  "$REPO_ROOT/experiments/reports" \
  "$REPO_ROOT/benchmarks/tpch/generated" \
  "$REPO_ROOT/benchmarks/tpch/data"

if [[ ! -f "$REPO_ROOT/env/compose/.env" ]]; then
  cp "$REPO_ROOT/env/compose/.env.example" "$REPO_ROOT/env/compose/.env"
  printf 'created %s/env/compose/.env\n' "$REPO_ROOT"
fi

find "$REPO_ROOT/scripts" -type f -name '*.sh' -exec chmod +x {} +

printf 'initialized local experiment workspace at %s\n' "$REPO_ROOT"
