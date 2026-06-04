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
TPCH_SUMMARY=""

if [[ -f "$RUN_DIR/tp/sysbench-run.log" ]]; then
  TP_LOG="$RUN_DIR/tp/sysbench-run.log"
elif [[ -f "$RUN_DIR/tp/tpcc-run.log" ]]; then
  TP_LOG="$RUN_DIR/tp/tpcc-run.log"
fi

if [[ -f "$RUN_DIR/tp/tpch/summary.tsv" ]]; then
  TPCH_SUMMARY="$RUN_DIR/tp/tpch/summary.tsv"
fi

PYTHON_CMD="$(command -v python3 || command -v python || true)"
[[ -n "$PYTHON_CMD" ]] || { printf 'python3 or python is required\n' >&2; exit 1; }

"$PYTHON_CMD" - "$RUN_DIR" "$TP_LOG" "$TPCH_SUMMARY" "$RESULT_FILE" <<'PY'
import csv
import pathlib
import re
import statistics
import sys

run_dir = pathlib.Path(sys.argv[1])
tp_log = pathlib.Path(sys.argv[2]) if sys.argv[2] else None
tpch_summary = pathlib.Path(sys.argv[3]) if sys.argv[3] else None
result_file = pathlib.Path(sys.argv[4])

samples = []
if tp_log and tp_log.exists():
    for line in tp_log.read_text(encoding='utf-8', errors='ignore').splitlines():
        match = re.search(r"tps:\s*([0-9.]+)", line)
        if not match:
            match = re.search(r"Throughput \(requests/sec\):\s*([0-9.]+)", line)
        if match:
            samples.append(float(match.group(1)))

tpch_durations = []
if tpch_summary and tpch_summary.exists():
    with tpch_summary.open(encoding='utf-8', newline='') as handle:
        for row in csv.DictReader(handle, delimiter='\t'):
            value = row.get('duration_seconds')
            if value not in (None, ''):
                tpch_durations.append(float(value))

memory_file = run_dir / 'observability' / 'db-memory.tsv'
peak_temp = 0
peak_active_sessions = 0
peak_session_used = 0
peak_session_used_ratio = 0.0
peak_session_count = 0
max_work_mem = 0
max_query_mem = 0
max_query_max_mem = 0
max_process_memory = 0
if memory_file.exists():
    lines = memory_file.read_text(encoding='utf-8', errors='ignore').splitlines()[1:]
    for line in lines:
        cols = line.split('\t')
        if len(cols) >= 14:
            peak_session_used = max(peak_session_used, int(float(cols[4])))
            peak_session_used_ratio = max(peak_session_used_ratio, float(cols[6]))
            peak_active_sessions = max(peak_active_sessions, int(float(cols[7])))
            peak_session_count = max(peak_session_count, int(float(cols[8])))
            peak_temp = max(peak_temp, int(float(cols[9])))
            max_work_mem = max(max_work_mem, int(float(cols[10])))
            max_query_mem = max(max_query_mem, int(float(cols[11])))
            max_query_max_mem = max(max_query_max_mem, int(float(cols[12])))
            max_process_memory = max(max_process_memory, int(float(cols[13])))
        elif len(cols) >= 8:
            peak_active_sessions = max(peak_active_sessions, int(float(cols[6])))
            peak_temp = max(peak_temp, int(float(cols[7])))

avg_tps = statistics.mean(samples) if samples else 0.0
min_tps = min(samples) if samples else 0.0
jitter_pct = ((avg_tps - min_tps) / avg_tps * 100.0) if avg_tps else 0.0

tpch_query_count = len(tpch_durations)
tpch_total_duration = sum(tpch_durations)
tpch_avg_duration = statistics.mean(tpch_durations) if tpch_durations else 0.0
tpch_max_duration = max(tpch_durations) if tpch_durations else 0.0

lines = ["metric\tvalue"]
if tpch_query_count:
    lines.extend([
        f"tpch_query_count\t{tpch_query_count}",
        f"tpch_total_duration_seconds\t{tpch_total_duration:.4f}",
        f"tpch_avg_query_duration_seconds\t{tpch_avg_duration:.4f}",
        f"tpch_max_query_duration_seconds\t{tpch_max_duration:.4f}",
    ])
elif samples:
    lines.extend([
        f"avg_tps\t{avg_tps:.4f}",
        f"min_tps\t{min_tps:.4f}",
        f"tps_jitter_pct\t{jitter_pct:.4f}",
    ])
else:
    lines.extend([
        "avg_tps\t0.0000",
        "min_tps\t0.0000",
        "tps_jitter_pct\t0.0000",
    ])

lines.extend([
    f"peak_active_sessions\t{peak_active_sessions}",
    f"peak_session_count\t{peak_session_count}",
    f"peak_session_used_bytes\t{peak_session_used}",
    f"peak_session_used_ratio\t{peak_session_used_ratio:.6f}",
    f"peak_temp_bytes\t{peak_temp}",
    f"max_work_mem_bytes\t{max_work_mem}",
    f"max_query_mem_bytes\t{max_query_mem}",
    f"max_query_max_mem_bytes\t{max_query_max_mem}",
    f"max_process_memory_bytes\t{max_process_memory}",
])

result_file.write_text("\n".join(lines) + "\n", encoding='utf-8')
PY

if [[ -n "$SUMMARY_FILE" ]]; then
  cat "$RESULT_FILE" >> "$SUMMARY_FILE"
fi

printf 'wrote %s\n' "$RESULT_FILE"
