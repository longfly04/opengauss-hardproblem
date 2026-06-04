#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR_BENCHMARK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR_BENCHMARK/../lib/common.sh"

INPUT_DIR=""
OUTPUT_DIR=""
ANALYSIS_NAME=""
RUN_ID=""
SCENARIO_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-dir)
      INPUT_DIR="$2"
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift
      ;;
    --analysis-name)
      ANALYSIS_NAME="$2"
      shift
      ;;
    --run-id)
      RUN_ID="$2"
      shift
      ;;
    --scenario-name)
      SCENARIO_NAME="$2"
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

[[ -n "$INPUT_DIR" ]] || fail "--input-dir is required"
[[ -n "$OUTPUT_DIR" ]] || fail "--output-dir is required"

mkdir -p "$OUTPUT_DIR"

args=(
  --input-dir "$INPUT_DIR"
  --output-dir "$OUTPUT_DIR"
)

if [[ -n "$ANALYSIS_NAME" ]]; then
  args+=(--analysis-name "$ANALYSIS_NAME")
fi
if [[ -n "$RUN_ID" ]]; then
  args+=(--run-id "$RUN_ID")
fi
if [[ -n "$SCENARIO_NAME" ]]; then
  args+=(--scenario-name "$SCENARIO_NAME")
fi

python3 "$SCRIPT_DIR_BENCHMARK/analyze-plan-batch.py" "${args[@]}"
