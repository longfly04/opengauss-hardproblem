#!/usr/bin/env bash
set -euo pipefail

RUN_DIR=""
SUMMARY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift
      ;;
    --summary-file)
      SUMMARY_FILE="$2"
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
SUMMARY_FILE="${SUMMARY_FILE:-$RUN_DIR/run-summary.env}"
RESULT_FILE="$RUN_DIR/validation-summary.tsv"
TP_LOG=""

if [[ -f "$RUN_DIR/tp/sysbench-run.log" ]]; then
  TP_LOG="$RUN_DIR/tp/sysbench-run.log"
elif [[ -f "$RUN_DIR/tp/tpcc-run.log" ]]; then
  TP_LOG="$RUN_DIR/tp/tpcc-run.log"
fi

PYTHON_CMD="$(command -v python3 || command -v python || true)"
[[ -n "$PYTHON_CMD" ]] || { printf 'python3 or python is required\n' >&2; exit 1; }

"$PYTHON_CMD" - "$RUN_DIR" "$TP_LOG" "$RESULT_FILE" <<'PY'
import pathlib
import re
import statistics
import sys

run_dir = pathlib.Path(sys.argv[1])
tp_log = pathlib.Path(sys.argv[2]) if sys.argv[2] else None
result_file = pathlib.Path(sys.argv[3])

samples = []
if tp_log and tp_log.exists():
    for line in tp_log.read_text(encoding='utf-8', errors='ignore').splitlines():
        match = re.search(r"tps:\s*([0-9.]+)", line)
        if not match:
            match = re.search(r"Throughput \(requests/sec\):\s*([0-9.]+)", line)
        if match:
            samples.append(float(match.group(1)))

memory_file = run_dir / 'observability' / 'db-memory.tsv'
peak_temp = 0
peak_sessions = 0
if memory_file.exists():
    lines = memory_file.read_text(encoding='utf-8', errors='ignore').splitlines()[1:]
    for line in lines:
        cols = line.split('\t')
        if len(cols) >= 8:
            peak_sessions = max(peak_sessions, int(float(cols[6])))
            peak_temp = max(peak_temp, int(float(cols[7])))

avg_tps = statistics.mean(samples) if samples else 0.0
min_tps = min(samples) if samples else 0.0
jitter_pct = ((avg_tps - min_tps) / avg_tps * 100.0) if avg_tps else 0.0

result_file.write_text(
    "metric\tvalue\n"
    f"avg_tps\t{avg_tps:.4f}\n"
    f"min_tps\t{min_tps:.4f}\n"
    f"tps_jitter_pct\t{jitter_pct:.4f}\n"
    f"peak_active_sessions\t{peak_sessions}\n"
    f"peak_temp_bytes\t{peak_temp}\n",
    encoding='utf-8'
)
PY

if [[ -n "$SUMMARY_FILE" ]]; then
  cat "$RESULT_FILE" >> "$SUMMARY_FILE"
fi

printf 'wrote %s\n' "$RESULT_FILE"
