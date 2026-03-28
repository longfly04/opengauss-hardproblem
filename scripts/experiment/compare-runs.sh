#!/usr/bin/env bash
set -euo pipefail

RUN_DIR=""
BASELINE_DIR=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift
      ;;
    --baseline-dir)
      BASELINE_DIR="$2"
      shift
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

[[ -n "$RUN_DIR" ]] || { printf 'missing --run-dir\n' >&2; exit 1; }
OUTPUT_FILE="${OUTPUT_FILE:-$RUN_DIR/comparison.md}"
CURRENT_VALIDATION="$RUN_DIR/validation-summary.tsv"

if [[ -z "$BASELINE_DIR" ]]; then
  BASELINE_DIR="$RUN_DIR"
fi

BASELINE_VALIDATION="$BASELINE_DIR/validation-summary.tsv"

PYTHON_CMD="$(command -v python3 || command -v python || true)"
[[ -n "$PYTHON_CMD" ]] || { printf 'python3 or python is required\n' >&2; exit 1; }

"$PYTHON_CMD" - "$CURRENT_VALIDATION" "$BASELINE_VALIDATION" "$OUTPUT_FILE" <<'PY'
import pathlib
import sys

def read_metrics(path):
    metrics = {}
    p = pathlib.Path(path)
    if not p.exists():
        return metrics
    for line in p.read_text(encoding='utf-8', errors='ignore').splitlines()[1:]:
        if not line.strip():
            continue
        key, value = line.split('\t', 1)
        metrics[key] = value
    return metrics

current = read_metrics(sys.argv[1])
baseline = read_metrics(sys.argv[2])
out = pathlib.Path(sys.argv[3])
lines = ["# Experiment comparison", "", "| metric | current | baseline |", "| --- | --- | --- |"]
for key in sorted(set(current) | set(baseline)):
    lines.append(f"| {key} | {current.get(key, 'n/a')} | {baseline.get(key, 'n/a')} |")
out.write_text("\n".join(lines) + "\n", encoding='utf-8')
PY

printf 'wrote %s\n' "$OUTPUT_FILE"
