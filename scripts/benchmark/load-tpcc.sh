#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

SCALE_FACTOR=10
TERMINALS=32
DURATION_SECONDS=300
CONFIG_OUTPUT="$REPO_ROOT/benchmarks/tpcc/config/generated_tpcc_config.xml"
LOG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scalefactor)
      SCALE_FACTOR="$2"
      shift
      ;;
    --terminals)
      TERMINALS="$2"
      shift
      ;;
    --duration)
      DURATION_SECONDS="$2"
      shift
      ;;
    --config-output)
      CONFIG_OUTPUT="$2"
      shift
      ;;
    --output)
      LOG_FILE="$2"
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
compose build tpcc-runner

mkdir -p "$(dirname -- "$CONFIG_OUTPUT")"
mkdir -p "${LOG_FILE:+$(dirname -- "$LOG_FILE")}" 2>/dev/null || true

sed \
  -e "s|__JDBC_DRIVER__|org.opengauss.Driver|g" \
  -e "s|__JDBC_URL__|jdbc:opengauss://opengauss:5432/$DB_NAME?prepareThreshold=0|g" \
  -e "s|__DB_USER__|$BENCH_USER|g" \
  -e "s|__DB_PASSWORD__|$BENCH_PASSWORD|g" \
  -e "s|__SCALE_FACTOR__|$SCALE_FACTOR|g" \
  -e "s|__TERMINALS__|$TERMINALS|g" \
  -e "s|__DURATION_SECONDS__|$DURATION_SECONDS|g" \
  "$REPO_ROOT/benchmarks/tpcc/config/tpcc-config.template.xml" > "$CONFIG_OUTPUT"

container_config="/workspace/${CONFIG_OUTPUT#$REPO_ROOT/}"
cmd="cd /opt/benchbase && java -jar benchbase.jar -b tpcc -c '$container_config' --create=true --load=true"

if [[ -n "$LOG_FILE" ]]; then
  compose run --rm --no-deps tpcc-runner bash -lc "$cmd" | tee "$LOG_FILE"
else
  compose run --rm --no-deps tpcc-runner bash -lc "$cmd"
fi
