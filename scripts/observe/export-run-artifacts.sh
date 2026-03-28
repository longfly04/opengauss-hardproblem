#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

RUN_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

[[ -n "$RUN_DIR" ]] || fail "--run-dir is required"
mkdir -p "$RUN_DIR/compose" "$RUN_DIR/configs" "$RUN_DIR/prometheus"

cp "$ENV_FILE" "$RUN_DIR/configs/runtime.env"
cp "$REPO_ROOT/experiments/configs/base/environment.yaml" "$RUN_DIR/configs/" 2>/dev/null || true
cp "$REPO_ROOT/experiments/configs/base/database.yaml" "$RUN_DIR/configs/" 2>/dev/null || true
cp "$REPO_ROOT/experiments/configs/base/workloads.yaml" "$RUN_DIR/configs/" 2>/dev/null || true

compose ps > "$RUN_DIR/compose/compose-ps.txt" || true
compose logs --no-color --tail 200 opengauss og-memory-exporter prometheus grafana > "$RUN_DIR/compose/core-services.log" || true
"$REPO_ROOT/scripts/db/collect-settings.sh" "$RUN_DIR/configs/current-settings.tsv" || true
"$REPO_ROOT/scripts/observe/snapshot-metrics.sh" --output-dir "$RUN_DIR/prometheus" || true
