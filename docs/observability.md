# Observability

## 在线指标链路

当前 Grafana / Prometheus 统一通过 `tools/exporter/app.py` 暴露两类指标：

1. **实时数据库指标**
   - 来源：`lab_obs.*` 视图
   - 代表指标：
     - `opengauss_shared_context_*`
     - `opengauss_session_*`
     - `opengauss_activity_sessions`
     - `opengauss_temp_*`
     - `opengauss_setting_*`

2. **离线 / 运行工件指标**
   - 来源：`experiments/runs/<run-id>/`
   - 代表工件：
     - `validation-summary.tsv`
     - `tp/sysbench-run.log`
     - `tp/tpch/*.log`
     - `tp/tpch/*.plan`
     - `plan-analysis/<analysis>/query-summary.tsv`
     - `plan-analysis/<analysis>/operator-summary.tsv`
     - `injection/round-*/`
   - 代表指标：
     - `opengauss_run_validation_metric`
     - `opengauss_run_sysbench_*`
     - `opengauss_run_tpch_query_*`
     - `opengauss_plan_*`
     - `opengauss_injection_*`

这意味着现在不再依赖孤立的 `sysbench_log_exporter`；Prometheus 只抓取 `og-memory-exporter:9188`。

---

## 数据库内存观测

### 1. 共享内存 / 共享池
来源：`sql/observability/memory_pool_views.sql`

关键指标：
- `opengauss_shared_context_total_bytes`
- `opengauss_shared_context_used_bytes`
- `opengauss_shared_context_free_bytes`

### 2. 会话内存 / 会话压力
来源：`sql/observability/session_memory_views.sql`

关键指标：
- `opengauss_session_total_bytes`
- `opengauss_session_used_bytes`
- `opengauss_session_free_bytes`
- `opengauss_session_memory_used_ratio`
- `opengauss_session_query_elapsed_seconds`
- `opengauss_activity_sessions`

### 3. 参数层可见性
来源：`pg_settings`

关键指标：
- `opengauss_setting_bytes{setting="work_mem"}`
- `opengauss_setting_bytes{setting="query_mem"}`
- `opengauss_setting_bytes{setting="query_max_mem"}`
- `opengauss_setting_bytes{setting="memorypool_size"}`
- `opengauss_setting_bytes{setting="max_process_memory"}`
- `opengauss_setting_bytes{setting="shared_buffers"}`
- `opengauss_setting_flag{setting="memorypool_enable"}`
- `opengauss_setting_flag{setting="enable_memory_limit"}`

### 4. Spill / Temp IO
来源：`sql/observability/spill_views.sql`

关键指标：
- `opengauss_temp_files_total`
- `opengauss_temp_bytes_total`

---

## 算子级 work_mem / spill 证据链

### Sort / Incremental Sort
这是当前最直接的算子级 work_mem 证据来源：
- `opengauss_plan_operator_sort_space_used_kb_max`
- `opengauss_plan_query_external_sort_nodes`
- `opengauss_plan_operator_temp_written_blocks_sum`
- `opengauss_plan_operator_exclusive_duration_ms_sum`

判读方式：
- `sort_space_used_kb_max` 反映排序阶段占用的工作内存量级；
- `external_sort_nodes` 和 `temp_written_blocks_sum` 说明排序已经溢出到磁盘；
- 再结合 `work_mem`、`query_mem`、会话内存压力和 temp bytes，可判断是局部算子压力还是整体内存池压力。

### Hash / Hash Join / HashAggregate
当前仍以间接证据为主：
- `opengauss_plan_operator_temp_written_blocks_sum{node_type=~"Hash|Hash Join|HashAggregate|Aggregate"}`
- `opengauss_plan_operator_exclusive_duration_ms_sum{node_type=~"Hash|Hash Join|HashAggregate|Aggregate"}`
- `opengauss_temp_bytes_total`
- `opengauss_session_used_bytes`
- `opengauss_shared_context_used_bytes`
- `opengauss_setting_bytes{setting=~"query_mem|query_max_mem|work_mem|max_process_memory"}`

后续如果 text plan / JSON plan 中出现稳定的 `Memory Usage`、`Peak Memory Usage`、`Disk Usage`、`Batches` 字段，应优先标准化导出为更直接的 hash work_mem 指标。

---

## 6 组仪表盘职责

### 1. Execution Plan Analysis
职责：离线 query / operator 证据。

重点面板：
- Parsed plans / queries / operators
- Invalid operator rows
- Duration-sane queries / Flagged queries
- Slowest sane queries
- Spill-heavy queries
- Operator duration / cost hotspots
- Sort memory evidence
- Sort/hash spill pressure

注意：
- 该 dashboard 现在会显式显示 `duration_sanity_ok=0` 的 query；
- 对历史旧工件中的异常值，会在 exporter 中标记为 flagged，并在主 TopN 图中排除。

### 2. openGauss Memory Overview
职责：实时共享池、会话池、temp IO 和关键参数总览。

重点面板：
- Shared pool bytes
- Session memory bytes
- Temp bytes / temp files
- Session state distribution
- Effective memory settings
- Top session used bytes / used ratio / query age
- Top shared contexts by used bytes

### 3. Pressure Injection Analysis
职责：注入事件与前台退化分析。

重点面板：
- Injection rounds
- Foreground TPS / P95 latency / errors
- Injection query runtime
- Injection temp written blocks
- Injection external sort nodes
- Injection query invalid operators

### 4. Sysbench Run Analysis
职责：真实 `tp/sysbench-run.log` 逐秒指标展示。

重点面板：
- TPS
- QPS
- Read / write / other QPS
- P95 latency
- Errors / reconnections
- Avg TPS / Min TPS / TPS jitter / peak temp bytes

### 5. TPCC Run Analysis
职责：当前阶段展示 **TPCC 命名场景下的 sysbench runner 指标**。

原因：
- 现有 `tpcc-steady` / `tpcc-plus-tpch-injection` 场景实际是 sysbench 驱动；
- 仓库中还没有稳定落盘的 `tp/tpcc-run.log` 工件，因此不能伪造 TPCC 原生日志图表。

后续演进：
- 一旦 `scripts/benchmark/run-tpcc.sh` 生成稳定的 `tp/tpcc-run.log` 或 summary TSV/JSON，应把该 dashboard 切换到真实 BenchBase TPCC 指标。

### 6. TPCH Run Analysis
职责：TPCH query 维度运行结果与 plan-analysis 联动分析。

重点面板：
- Query count / total duration / avg / max
- Per-query duration
- Per-query plan runtime
- Spill-heavy queries
- Queries with external sorts
- Operator duration hotspots
- Operator sort-space evidence
- Flagged plan queries

---

## 工件兼容性说明

### 1. 历史旧 run 可能缺少 `tp/tpch/summary.tsv`
当前 exporter 会优先使用 `summary.tsv`；如果缺失，会回退到：
- `plan-analysis/tpch/query-summary.tsv`
- `tp/tpch/*.plan`
- `tp/tpch/*.log`

因此旧 TPCH run 也能在 dashboard 中显示 query 级结果。

### 2. 历史旧 plan-analysis 可能仍带异常时长
例如某些旧 `query-summary.tsv` 仍可能保留修复前的异常值。当前 exporter 的处理策略是：
- 将超出 sanity 上限的 query 标记为 `duration_sanity_ok=0`；
- 将这些 query 从主 TopN 面板中排除；
- 在 quality 面板中显式暴露 invalid / flagged 状态。

如果你希望旧 run 完全恢复为“正常值”，仍建议对对应 `.plan` 重新执行：
```bash
bash scripts/benchmark/analyze-plan-batch.sh \
  --input-dir experiments/runs/<run-id>/injection/round-1 \
  --output-dir experiments/runs/<run-id>/plan-analysis/round-1
```

---

## 相关文件
- `tools/exporter/app.py`
- `sql/observability/memory_pool_views.sql`
- `sql/observability/session_memory_views.sql`
- `sql/observability/spill_views.sql`
- `env/grafana/dashboards/execution-plan-analysis.json`
- `env/grafana/dashboards/opengauss-memory-overview.json`
- `env/grafana/dashboards/pressure-injection-analysis.json`
- `env/grafana/dashboards/sysbench-run-analysis.json`
- `env/grafana/dashboards/tpcc-run-analysis.json`
- `env/grafana/dashboards/tpch-run-analysis.json`
