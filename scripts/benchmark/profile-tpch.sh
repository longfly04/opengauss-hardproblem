#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR_BENCHMARK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR_BENCHMARK/../lib/common.sh"

QUERY_DIR="$REPO_ROOT/benchmarks/tpch/variants/pressure-injection"
OUTPUT_DIR="$REPO_ROOT/experiments/reports/tpch-execution-plan"
ANALYSIS_DIR="$OUTPUT_DIR/plan-analysis"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query-dir)
      QUERY_DIR="$2"
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      ANALYSIS_DIR="$OUTPUT_DIR/plan-analysis"
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

ensure_env_file
mkdir -p "$OUTPUT_DIR"

printf 'running TPCH plans into %s\n' "$OUTPUT_DIR"
"$SCRIPT_DIR_BENCHMARK/run-tpch.sh" --query-dir "$QUERY_DIR" --output-dir "$OUTPUT_DIR"
"$SCRIPT_DIR_BENCHMARK/analyze-plan-batch.sh" \
  --input-dir "$OUTPUT_DIR" \
  --output-dir "$ANALYSIS_DIR" \
  --analysis-name "$(basename -- "$ANALYSIS_DIR")"

printf 'wrote %s\n' "$ANALYSIS_DIR"

