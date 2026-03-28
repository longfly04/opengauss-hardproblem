# Observability

## 数据库内存观测
### 1. 共享内存
- 视图文件：[sql/observability/memory_pool_views.sql](../sql/observability/memory_pool_views.sql)
- 主要来源：`gs_shared_memory_detail`
- 关键指标：
  - `opengauss_shared_context_total_bytes`
  - `opengauss_shared_context_used_bytes`
  - `opengauss_shared_context_free_bytes`

### 2. 会话内存
- 视图文件：[sql/observability/session_memory_views.sql](../sql/observability/session_memory_views.sql)
- 主要来源：`gs_session_memory_detail`、`pg_stat_activity`
- 关键指标：
  - `opengauss_session_total_bytes`
  - `opengauss_session_used_bytes`
  - `opengauss_activity_sessions`

### 3. 落盘 / temp IO
- 视图文件：[sql/observability/spill_views.sql](../sql/observability/spill_views.sql)
- 主要来源：`summary_stat_database`
- 关键指标：
  - `opengauss_temp_files_total`
  - `opengauss_temp_bytes_total`

## 仪表盘
- [env/grafana/dashboards/opengauss-memory-overview.json](../env/grafana/dashboards/opengauss-memory-overview.json)
- [env/grafana/dashboards/tpcc-run-analysis.json](../env/grafana/dashboards/tpcc-run-analysis.json)
- [env/grafana/dashboards/pressure-injection-analysis.json](../env/grafana/dashboards/pressure-injection-analysis.json)

## 离线采样
- `scripts/observe/sample-db-memory.sh`
- `scripts/observe/snapshot-metrics.sh`
- `scripts/observe/export-run-artifacts.sh`

其中 `sample-db-memory.sh` 会把共享内存、会话内存、活跃会话、temp bytes 以时间序列写入 TSV，适合后处理或画图。
