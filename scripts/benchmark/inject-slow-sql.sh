#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

DELAY_SECONDS=60
QUERY_DIR=""
REPEAT=1
OUTPUT_DIR=""
SLEEP_BETWEEN_ROUNDS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delay)
      DELAY_SECONDS="$2"
      shift
      ;;
    --query-dir)
      QUERY_DIR="$2"
      shift
      ;;
    --repeat)
      REPEAT="$2"
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift
      ;;
    --sleep-between-rounds)
      SLEEP_BETWEEN_ROUNDS="$2"
      shift
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$QUERY_DIR" || -z "$OUTPUT_DIR" ]]; then
  printf 'usage: %s --query-dir <dir> --output-dir <dir> [--delay n] [--repeat n]\n' "$0" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
sleep "$DELAY_SECONDS"
date +%s > "$OUTPUT_DIR/injection_start_epoch.txt"

for round in $(seq 1 "$REPEAT"); do
  round_dir="$OUTPUT_DIR/round-$round"
  mkdir -p "$round_dir"
  "$SCRIPT_DIR/run-tpch.sh" --query-dir "$QUERY_DIR" --output-dir "$round_dir"
  if [[ "$round" -lt "$REPEAT" ]]; then
    sleep "$SLEEP_BETWEEN_ROUNDS"
  fi
done
