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
# 只在镜像不存在时构建
docker image inspect local/opengauss-tpcc-runner:latest >/dev/null 2>&1 || compose build tpcc-runner

mkdir -p "$(dirname -- "$CONFIG_OUTPUT")"
mkdir -p "${LOG_FILE:+$(dirname -- "$LOG_FILE")}" 2>/dev/null || true

# 使用容器内部端口 5432，而不是主机映射端口
JDBC_URL="jdbc:postgresql://$DB_HOST:5432/$DB_NAME?prepareThreshold=0"

sed \
  -e "s|__JDBC_URL__|$JDBC_URL|g" \
  -e "s|__DB_USER__|$BENCH_USER|g" \
  -e "s|__DB_PASSWORD__|$BENCH_PASSWORD|g" \
  -e "s|__SCALE_FACTOR__|$SCALE_FACTOR|g" \
  -e "s|__TERMINALS__|$TERMINALS|g" \
  -e "s|__DURATION_SECONDS__|$DURATION_SECONDS|g" \
  "$REPO_ROOT/benchmarks/tpcc/config/tpcc-config.template.xml" > "$CONFIG_OUTPUT"

container_config="/workspace/${CONFIG_OUTPUT#$REPO_ROOT/}"
cmd="benchbase -b tpcc -c '$container_config' --create=true --load=true"

log "Executing TPCC data load with command: $cmd"
log "This may take several minutes..."

if [[ -n "$LOG_FILE" ]]; then
  log "Logging output to: $LOG_FILE"
  # 使用-d参数在后台运行，并使用docker logs查看输出
  compose run --name tpcc-load-temp --rm -d tpcc-runner bash -lc "$cmd > /tmp/tpcc-load.log 2>&1"
  # 等待命令执行完成
  while docker ps -f name=tpcc-load-temp --format '{{.Status}}' | grep -q 'Up'; do
    sleep 5
    # 显示最新的日志输出
    docker logs tpcc-load-temp --tail 10
  done
  # 将容器内的日志复制到本地
  docker cp tpcc-load-temp:/tmp/tpcc-load.log "$LOG_FILE"
else
  compose run --rm --no-deps tpcc-runner bash -lc "$cmd"
fi
