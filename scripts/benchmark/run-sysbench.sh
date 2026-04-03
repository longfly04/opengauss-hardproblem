#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

MODE="run"
THREADS=64
TIME_SECONDS=180
REPORT_INTERVAL=1
TABLES=8
TABLE_SIZE=50000
OUTPUT_FILE=""
WORKLOAD="oltp_read_write"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift
      ;;
    --threads)
      THREADS="$2"
      shift
      ;;
    --time)
      TIME_SECONDS="$2"
      shift
      ;;
    --report-interval)
      REPORT_INTERVAL="$2"
      shift
      ;;
    --tables)
      TABLES="$2"
      shift
      ;;
    --table-size)
      TABLE_SIZE="$2"
      shift
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift
      ;;
    --workload)
      WORKLOAD="$2"
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

ensure_cmd docker
ensure_env_file

# 使用容器内部端口 5432，而不是主机映射端口
# 注意：sysbench 容器的 ENTRYPOINT 已经是 sysbench，所以不需要前缀
cmd="--db-driver=pgsql --pgsql-host=$DB_HOST --pgsql-port=5432 --pgsql-db=$DB_NAME --pgsql-user=$BENCH_USER --pgsql-password=$BENCH_PASSWORD --tables=$TABLES --table-size=$TABLE_SIZE --report-interval=$REPORT_INTERVAL --threads=$THREADS --time=$TIME_SECONDS $WORKLOAD"

case "$MODE" in
  prepare)
    cmd="$cmd prepare"
    ;;
  run)
    cmd="$cmd run"
    ;;
  cleanup)
    cmd="$cmd cleanup"
    ;;
  *)
    fail "unsupported mode: $MODE"
    ;;
esac

mkdir -p "${OUTPUT_FILE:+$(dirname -- "$OUTPUT_FILE")}" 2>/dev/null || true

if [[ -n "$OUTPUT_FILE" ]]; then
  compose run --rm --no-deps sysbench $cmd | tee "$OUTPUT_FILE"
else
  compose run --rm --no-deps sysbench $cmd
fi
