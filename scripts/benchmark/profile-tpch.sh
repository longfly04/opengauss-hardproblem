#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR_BENCHMARK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR_BENCHMARK/../lib/common.sh"

QUERY_DIR="$REPO_ROOT/benchmarks/tpch/variants/pressure-injection"
OUTPUT_DIR="$REPO_ROOT/experiments/reports/tpch-execution-plan"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query-dir)
      QUERY_DIR="$2"
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
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

# 启动openGauss服务
echo "启动openGauss服务..."
compose up -d opengauss
wait_for_db

# 加载TPCH数据
echo "加载TPCH数据..."
bash "$SCRIPT_DIR_BENCHMARK/load-tpch.sh" --scale-factor 1

# 初始化统计数据文件
STATISTICS_FILE="$OUTPUT_DIR/statistics.csv"
echo "Node Type,Memory Used (MB),Execution Time (ms),Rows Processed,Query Name" > "$STATISTICS_FILE"

# 运行TPCH查询并分析执行计划
for sql_file in "$QUERY_DIR"/*.sql; do
  query_name="$(basename -- "$sql_file")"
  query_base="${query_name%.sql}"
  plan_dir="$OUTPUT_DIR/$query_base"
  mkdir -p "$plan_dir"
  
  echo "分析查询: $query_name"
  
  # 将SQL查询复制到容器中
  compose cp "$sql_file" "$DB_SERVICE_NAME":/tmp/query.sql
  
  # 创建包含EXPLAIN命令的临时文件
  compose exec -T -u "$DB_CONTAINER_USER" "$DB_SERVICE_NAME" bash -c "echo 'EXPLAIN (ANALYZE, VERBOSE, COSTS, BUFFERS, FORMAT text)' > /tmp/explain_query.sql && cat /tmp/query.sql >> /tmp/explain_query.sql"
  
  # 获取执行计划
  echo "获取执行计划..."
  compose exec -T -u "$DB_CONTAINER_USER" "$DB_SERVICE_NAME" bash -c "$DB_CLIENT_BIN -d $DB_NAME -f /tmp/explain_query.sql" > "$plan_dir/execution_plan.txt"
  
  # 执行原始查询
  echo "执行查询..."
  compose exec -T -u "$DB_CONTAINER_USER" "$DB_SERVICE_NAME" bash -c "$DB_CLIENT_BIN -d $DB_NAME -f /tmp/query.sql" > "$plan_dir/query_output.txt"
  
  # 解析执行计划并提取节点信息
  echo "解析执行计划..."
  
  # 提取hash join节点信息
  grep -A 15 "Hash Join" "$plan_dir/execution_plan.txt" | while read -r line; do
    # 初始化变量
    memory_kb="0"
    memory_mb="0"
    exec_time="0"
    rows="0"
    
    if [[ $line =~ Memory:([0-9]+)kB ]]; then
      memory_kb="${BASH_REMATCH[1]}"
      memory_mb=$(echo "scale=2; $memory_kb / 1024" | bc)
    elif [[ $line =~ Memory\ Usage:([0-9]+)kB ]]; then
      memory_kb="${BASH_REMATCH[1]}"
      memory_mb=$(echo "scale=2; $memory_kb / 1024" | bc)
    fi
    if [[ $line =~ actual time=([0-9.]+)..([0-9.]+) ]]; then
      exec_time="${BASH_REMATCH[2]}"
    fi
    if [[ $line =~ rows=([0-9]+) ]]; then
      rows="${BASH_REMATCH[1]}"
      # 记录hash join节点信息
      echo "Hash Join,$memory_mb,$exec_time,$rows,$query_name" >> "$STATISTICS_FILE"
    fi
  done
  
  # 提取其他类型的节点信息（如Seq Scan、Index Scan等）
  grep -E "(Seq Scan|Index Scan|Sort|Aggregate|Nested Loop)" "$plan_dir/execution_plan.txt" | while read -r line; do
    node_type=$(echo "$line" | grep -E -o "(Seq Scan|Index Scan|Sort|Aggregate|Nested Loop)")
    exec_time="0"
    rows="0"
    if [[ $line =~ actual time=([0-9.]+)..([0-9.]+) ]]; then
      exec_time="${BASH_REMATCH[2]}"
    fi
    if [[ $line =~ rows=([0-9]+) ]]; then
      rows="${BASH_REMATCH[1]}"
    fi
    # 记录节点信息
    echo "$node_type,,$exec_time,$rows,$query_name" >> "$STATISTICS_FILE"
  done
  
  echo "执行计划分析完成: $plan_dir/execution_plan.txt"
done

# 生成统计分析报告
echo "生成统计分析报告..."

# 分析hash join节点的内存使用分布
HASH_JOIN_STATS="$OUTPUT_DIR/hash_join_memory_stats.txt"
echo "Hash Join Memory Usage Analysis" > "$HASH_JOIN_STATS"
echo "================================" >> "$HASH_JOIN_STATS"

# 计算hash join的平均内存使用
avg_memory=$(grep "Hash Join" "$STATISTICS_FILE" | cut -d ',' -f 2 | awk '{sum += $1} END {print sum / NR}')
echo "Average Memory Used: $avg_memory MB" >> "$HASH_JOIN_STATS"

# 计算hash join的内存使用标准差
std_memory=$(grep "Hash Join" "$STATISTICS_FILE" | cut -d ',' -f 2 | awk -v avg="$avg_memory" '{sum += ($1 - avg)^2} END {print sqrt(sum / NR)}')
echo "Standard Deviation: $std_memory MB" >> "$HASH_JOIN_STATS"

# 计算hash join的最大和最小内存使用
max_memory=$(grep "Hash Join" "$STATISTICS_FILE" | cut -d ',' -f 2 | sort -n | tail -1)
min_memory=$(grep "Hash Join" "$STATISTICS_FILE" | cut -d ',' -f 2 | sort -n | head -1)
echo "Max Memory Used: $max_memory MB" >> "$HASH_JOIN_STATS"
echo "Min Memory Used: $min_memory MB" >> "$HASH_JOIN_STATS"

# 分析hash join节点的执行时间分布
HASH_JOIN_TIME_STATS="$OUTPUT_DIR/hash_join_time_stats.txt"
echo "Hash Join Execution Time Analysis" > "$HASH_JOIN_TIME_STATS"
echo "==================================" >> "$HASH_JOIN_TIME_STATS"

# 计算hash join的平均执行时间
avg_time=$(grep "Hash Join" "$STATISTICS_FILE" | cut -d ',' -f 3 | awk '{sum += $1} END {print sum / NR}')
echo "Average Execution Time: $avg_time ms" >> "$HASH_JOIN_TIME_STATS"

# 计算hash join的执行时间标准差
std_time=$(grep "Hash Join" "$STATISTICS_FILE" | cut -d ',' -f 3 | awk -v avg="$avg_time" '{sum += ($1 - avg)^2} END {print sqrt(sum / NR)}')
echo "Standard Deviation: $std_time ms" >> "$HASH_JOIN_TIME_STATS"

# 计算hash join的最大和最小执行时间
max_time=$(grep "Hash Join" "$STATISTICS_FILE" | cut -d ',' -f 3 | sort -n | tail -1)
min_time=$(grep "Hash Join" "$STATISTICS_FILE" | cut -d ',' -f 3 | sort -n | head -1)
echo "Max Execution Time: $max_time ms" >> "$HASH_JOIN_TIME_STATS"
echo "Min Execution Time: $min_time ms" >> "$HASH_JOIN_TIME_STATS"

# 分析所有节点类型的执行时间分布
ALL_NODES_TIME_STATS="$OUTPUT_DIR/all_nodes_time_stats.txt"
echo "All Node Types Execution Time Analysis" > "$ALL_NODES_TIME_STATS"
echo "======================================" >> "$ALL_NODES_TIME_STATS"

# 按节点类型分组计算平均执行时间
awk -F ',' 'NR > 1 {node_type[$1] += $3; count[$1] += 1} END {for (type in node_type) print type ": " node_type[type]/count[type] " ms"}' "$STATISTICS_FILE" >> "$ALL_NODES_TIME_STATS"

echo "统计分析报告已生成:"
echo "- 原始统计数据: $STATISTICS_FILE"
echo "- Hash Join内存使用分析: $HASH_JOIN_STATS"
echo "- Hash Join执行时间分析: $HASH_JOIN_TIME_STATS"
echo "- 所有节点类型执行时间分析: $ALL_NODES_TIME_STATS"

echo "执行计划分析完成！"

