#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

DELAY_SECONDS=60
QUERY_DIR=""
QUERY_FILE=""
REPEAT=1
OUTPUT_DIR=""
SLEEP_BETWEEN_ROUNDS=5
PLAN_MODE="analyze"
QUERY_TIMEOUT_SECONDS=0

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
    --query-file)
      QUERY_FILE="$2"
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
    --plan-mode)
      PLAN_MODE="$2"
      shift
      ;;
    --query-timeout-seconds)
      QUERY_TIMEOUT_SECONDS="$2"
      shift
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$OUTPUT_DIR" ]]; then
  printf 'usage: %s [--query-dir <dir> | --query-file <file>] --output-dir <dir> [--delay n] [--repeat n]\n' "$0" >&2
  exit 1
fi

if [[ -z "$QUERY_DIR" && -z "$QUERY_FILE" ]]; then
  printf 'one of --query-dir or --query-file is required\n' >&2
  exit 1
fi

if [[ -n "$QUERY_DIR" && -n "$QUERY_FILE" ]]; then
  printf 'only one of --query-dir or --query-file can be set\n' >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
sleep "$DELAY_SECONDS"
date +%s > "$OUTPUT_DIR/injection_start_epoch.txt"

for round in $(seq 1 "$REPEAT"); do
  round_dir="$OUTPUT_DIR/round-$round"
  mkdir -p "$round_dir"
  run_args=(
    --output-dir "$round_dir"
    --plan-mode "$PLAN_MODE"
    --query-timeout-seconds "$QUERY_TIMEOUT_SECONDS"
  )
  if [[ -n "$QUERY_FILE" ]]; then
    run_args+=(--query-file "$QUERY_FILE")
  else
    run_args+=(--query-dir "$QUERY_DIR")
  fi
  "$SCRIPT_DIR/run-tpch.sh" "${run_args[@]}"
  if [[ "$round" -lt "$REPEAT" ]]; then
    sleep "$SLEEP_BETWEEN_ROUNDS"
  fi
done
