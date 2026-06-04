# 最新能力与当前状态

本文档用于汇总本仓库**当前已经落地**的实验能力、指标链路、Grafana 看板职责、历史工件兼容策略，以及仍然存在的限制，便于快速理解“现在这套 openGauss Lab 到底能做什么”。

---

## 1. 本轮已落地的关键能力

### 1.1 离线执行计划异常值已修复

本轮首先修复了 `Execution Plan Analysis` 中最影响阅读的问题：

- 某些 openGauss text plan 的节点 `loops` 极大；
- 旧逻辑会把节点 `Actual Total Time` 再按 loops 放大；
- 最终在 `query-summary.tsv` / `operator-summary.tsv` 中出现“上千年”的执行时间；
- 这些异常值又会直接污染 Grafana Top-N 图表。

当前修复后的链路是：

1. `ThirdParty/pev2` 在 text plan 解析阶段引入 plan footer runtime sanity 约束；
2. `scripts/benchmark/analyze-plan-batch.py` 优先使用 footer runtime 作为 query 级执行时长；
3. 异常 operator 行会被标记并在 Top-N 聚合时过滤；
4. exporter 会暴露 plan 数据质量指标，Grafana 可以显式展示 flagged query / invalid rows。

当前重点质量字段与指标：

- `runtime_source`
- `duration_sanity_status`
- `invalid_operator_count`
- `opengauss_plan_query_duration_sanity_ok`
- `opengauss_plan_query_invalid_operator_count`
- `opengauss_plan_analysis_invalid_rows_total`

### 1.2 `tools/exporter/app.py` 已统一收敛为唯一 exporter

当前仓库中，**实时数据库指标**和**运行工件指标**都统一通过 `tools/exporter/app.py` 暴露，不再依赖孤立的 sysbench exporter。

Prometheus 当前只需要抓取：

- `og-memory-exporter:9188`
- `prometheus:9090`
- `node-exporter:9100`
- `cadvisor:8080`

其中项目自定义指标只来自 `og-memory-exporter:9188`。

### 1.3 运行工件指标已被统一纳入 Prometheus

当前 `app.py` 会从 `experiments/runs/<run-id>/` 读取并暴露：

- `validation-summary.tsv` → `opengauss_run_validation_metric`
- `tp/sysbench-run.log` → `opengauss_run_sysbench_*`
- `tp/tpch/*.plan`、`tp/tpch/*.log`、`tp/tpch/summary.tsv`、`plan-analysis/tpch/*` → `opengauss_run_tpch_query_*`、`opengauss_tpch_run_*`
- `plan-analysis/*` → `opengauss_plan_*`
- `injection/round-*` + `plan-analysis/round-*` → `opengauss_injection_*`

### 1.4 六组 Grafana dashboard 已重新定义职责

当前 `openGauss Lab` 下的 6 组 dashboard 不再重复展示同一批无意义图表，而是各自回答一个明确问题：

1. `openGauss Memory Overview`
2. `Execution Plan Analysis`
3. `Pressure Injection Analysis`
4. `Sysbench Run Analysis`
5. `TPCC Run Analysis`
6. `TPCH Run Analysis`

### 1.5 历史 run 的兼容能力已增强

当前 exporter 已兼容两类旧工件问题：

1. 旧 TPCH run 缺少 `tp/tpch/summary.tsv`
   - 会自动回退到 `plan-analysis/tpch/query-summary.tsv`、`tp/tpch/*.plan`、`tp/tpch/*.log`
2. 旧 plan-analysis 工件仍包含修复前的异常 duration
   - exporter 会将其标记为 flagged query，并从主 Top-N 图中排除

这意味着旧运行结果即使没有被重新生成，也仍然可以进入当前 Grafana 视图，但会被质量面板标出来。

### 1.6 source / stock 启停链路已验证打通

当前双运行模式的核心链路已经完成回归验证：

- `bash scripts/db/build-source.sh` 可成功构建 `opengauss-dev` 与 source runtime；
- `bash scripts/db/build-source.sh --emit-stock-image` 可成功生成 trusted stock baseline image；
- `bash scripts/db/start.sh --mode source --full-observability` 与 `bash scripts/db/start.sh --mode stock --full-observability` 都已验证可完成健康检查、bootstrap SQL、observability 视图安装与 `select 1` 连通性检查。

为打通这条链路，当前仓库已同时具备以下运行时修正：

- source runtime / `opengauss-dev` 的调试端口已拆分，但 benchmark / experiment 仍共用同一个 `DB_PORT`；
- runtime / stock image 已补齐 source build 所需的 third_party 运行时动态库；
- runtime / stock image 已补齐 locale 支持，可兼容历史 `en_US.utf8` 数据目录；
- source mode 启动时会兼容 `${OPENGAUSS_DATA_DIR}` 与 `${OPENGAUSS_DATA_DIR}/data` 两类历史数据目录布局。

### 1.7 本轮 3 个回归问题已完成闭环验证

截至当前文档版本，用户此前报告的 3 个高优先级回归都已经完成代码修复并做过实跑验证：

1. `tpcc-steady.yaml` 的 sysbench 时序链路已恢复
   - exporter 侧修复了 shared-memory context 重复 label 导致的 scrape 污染；
   - sysbench 工件导出被收敛为仅保留近期 run，避免历史显式时间戳持续污染 Prometheus；
   - 在重建 `prometheus_data` volume 后，重新运行 `20260417-103225-tpcc-steady`，已确认 Prometheus 能查询到：
     - `opengauss_run_sysbench_tps`
     - `opengauss_run_sysbench_qps`
     - `opengauss_run_sysbench_latency_p95_ms`
   - 上述 3 组指标在该 run 上都已验证有 301 个采样点，足以驱动 `Sysbench Run Analysis` 与 `TPCC Run Analysis` 当前的 sysbench-derived 面板。

2. `tpch-baseline.yaml` 的 seed 复用路径已恢复
   - `load-tpch.sh` 不再调用 openGauss 不兼容的 `to_regclass()`；
   - 当前改为 `pg_class + pg_namespace` existence-check 语义；
   - `20260416-224450-tpch-baseline` 已验证可以直接复用已有 TPCH seed，不再触发 `function to_regclass(unknown) does not exist`。

3. stock mode 已稳定指向本地 trusted baseline image
   - `common.sh` 会自动把 legacy `OPENGAUSS_IMAGE` 远端 tag 归一化到 `local/opengauss-stock-baseline:latest`；
   - `start.sh --mode stock` 在本地 baseline image 缺失时会自动触发源码编译并生成 trusted stock image；
   - 实跑验证中，`oglab-opengauss` 已确认运行在 `local/opengauss-stock-baseline:latest`，而不是历史远端镜像。

---

## 2. 当前统一指标链路

### 2.1 在线数据库指标链路

```text
openGauss
  -> lab_obs.* SQL views
  -> tools/exporter/app.py
  -> Prometheus
  -> Grafana
```

主要来源：

- `sql/observability/memory_pool_views.sql`
- `sql/observability/session_memory_views.sql`
- `sql/observability/spill_views.sql`
- `sql/observability/execution_plan_views.sql`

主要指标族：

- `opengauss_shared_*`
- `opengauss_session_*`
- `opengauss_activity_sessions`
- `opengauss_temp_*`
- `opengauss_setting_*`

### 2.2 离线 / 运行工件指标链路

```text
shell scripts
  -> benchmark / scenario artifacts under experiments/runs/
  -> tools/exporter/app.py
  -> Prometheus
  -> Grafana
```

其中执行计划批处理链路为：

```text
scripts/benchmark/analyze-plan-batch.sh
-> scripts/benchmark/analyze-plan-batch.py
  -> ThirdParty/pev2 Node CLI parser
    -> plan-analysis/* artifacts
      -> tools/exporter/app.py
```

主要工件指标族：

- `opengauss_run_validation_metric`
- `opengauss_run_sysbench_*`
- `opengauss_run_tpch_query_*`
- `opengauss_tpch_run_*`
- `opengauss_plan_*`
- `opengauss_injection_*`

### 2.3 统一 label 语义

当前 run-scoped 指标尽量统一使用这些标签：

- `run`
- `scenario`
- `analysis`
- `runner`
- `phase`
- `query_name`
- `node_type`

这样 Grafana 可以按一次具体运行、一个具体场景或一个具体查询进行筛选，而不是把不同 workload 混在一起。

---

## 3. 六组 dashboard 当前各自回答什么问题

### 3.1 `openGauss Memory Overview`

职责：回答“当前数据库共享池、会话池、temp IO 和关键参数处于什么状态”。

当前重点图表：

- shared pool bytes
- session memory bytes
- temp bytes / temp files
- session state distribution
- effective memory settings
- top session used bytes / used ratio / query age
- top shared contexts by used bytes

本轮已经移除/降级的误导性内容：

- 把恒定布尔 flag 作为主时序图展示
- 混合 bytes 与 files 的图表
- 大面积无意义 `no data` 占位图

### 3.2 `Execution Plan Analysis`

职责：回答“哪些 query/operator 最慢、最会 spill、哪些结果不可信”。

当前重点图表：

- parsed plans / queries / operators
- invalid operator rows
- duration-sane queries / flagged queries
- slowest sane queries
- spill-heavy queries
- operator duration / cost hotspots
- sort memory evidence
- sort/hash spill pressure

关键变化：

- 主 Top-N 面板会过滤 `duration_sanity_ok=0` 的 query；
- 异常 query 不再静默污染图表，而是被显式标记出来。

### 3.3 `Pressure Injection Analysis`

职责：回答“注入了什么查询、哪一轮最重、对前台 TPS/latency 造成了什么退化”。

当前重点图表：

- injection rounds
- foreground TPS / P95 latency / errors / reconn
- injection query runtime
- injection temp written blocks
- injection external sort nodes
- injection query invalid operators

### 3.4 `Sysbench Run Analysis`

职责：回答“真实 sysbench 运行过程中 TPS/QPS/latency 如何变化”。

当前重点图表：

- TPS
- QPS（总 / read / write / other）
- P95 latency
- errors / reconnections
- avg TPS / min TPS / TPS jitter / peak temp bytes

这些图表直接来自：

- `tp/sysbench-run.log`
- `validation-summary.tsv`

### 3.5 `TPCC Run Analysis`

职责：当前阶段主要用于明确提示**TPCC 命名场景与实际 runner 语义之间的关系**。

当前现实约束：

- `tpcc-steady.yaml` / `tpcc-plus-tpch-injection.yaml` 仍然是 **sysbench 驱动**；
- `run-tpcc.sh` 仍保留为 BenchBase-backed TPCC 能力；
- 但仓库中目前还没有稳定可复用的 `tp/tpcc-run.log` 历史工件链路。

因此当前 TPCC dashboard 不能假装在展示真实 BenchBase TPCC runner 指标，它会明确说明当前仍是 sysbench-derived 语义。

### 3.6 `TPCH Run Analysis`

职责：回答“哪些 TPCH query 慢、哪些 spill、哪些 operator 最重”。

当前重点图表：

- query count / total runtime / avg / max
- per-query duration
- per-query plan runtime
- spill-heavy queries
- queries with external sorts
- operator duration hotspots
- operator sort-space evidence
- flagged plan queries

---

## 4. 当前关键指标与证据链

### 4.1 共享池 / 会话池 / 参数可见性

主要指标：

- `opengauss_shared_context_total_bytes`
- `opengauss_shared_context_used_bytes`
- `opengauss_shared_context_free_bytes`
- `opengauss_session_total_bytes`
- `opengauss_session_used_bytes`
- `opengauss_session_free_bytes`
- `opengauss_session_memory_used_ratio`
- `opengauss_activity_sessions`
- `opengauss_setting_bytes{setting="work_mem"}`
- `opengauss_setting_bytes{setting="query_mem"}`
- `opengauss_setting_bytes{setting="query_max_mem"}`
- `opengauss_setting_bytes{setting="memorypool_size"}`
- `opengauss_setting_bytes{setting="max_process_memory"}`
- `opengauss_setting_bytes{setting="shared_buffers"}`

### 4.2 Sort / spill / temp evidence

当前最直接的算子级 `work_mem` 证据主要来自排序相关节点：

- `opengauss_plan_operator_sort_space_used_kb_max`
- `opengauss_plan_query_external_sort_nodes`
- `opengauss_plan_operator_temp_written_blocks_sum`
- `opengauss_plan_operator_exclusive_duration_ms_sum`
- `opengauss_temp_bytes_total`
- `opengauss_temp_files_total`

判读方法：

- `sort_space_used_kb_max` 代表排序阶段使用的工作内存量级；
- `external_sort_nodes`、`temp_written_blocks_sum` 说明已经发生外排 / spill；
- 再结合会话内存与参数层视图，可以判断是局部算子压力还是全局内存池压力。

### 4.3 Hash / Hash Join / HashAggregate evidence

当前 hash 类算子还主要依赖间接证据：

- `temp_written_blocks_sum`
- `exclusive_duration_ms_sum`
- `opengauss_temp_bytes_total`
- `opengauss_session_used_bytes`
- `opengauss_shared_context_used_bytes`
- `work_mem/query_mem/query_max_mem/max_process_memory`

如果后续 openGauss plan 能稳定输出 `Memory Usage`、`Peak Memory Usage`、`Disk Usage`、`Batches` 等字段，应优先把它们标准化为更直接的 hash work_mem 指标。

---

## 5. 当前场景语义

### 5.1 双运行模式

当前仓库仍然只有两种运行语义：

- `stock`：源码编译后打包出的可信 baseline image
- `source`：挂载源码并保留开发缓存的调试/开发模式

没有引入第三种运行模式。

当前推荐的运行约定是：

- `stock` 与 `source` 共用同一个 `DB_PORT`，这样 benchmark / experiment 脚本和场景配置无需因为模式切换而改端口；
- 若需要在两种模式之间切换，先 stop 当前模式，再 start 另一模式；
- `OPENGAUSS_DEBUG_PORT` 与 `OPENGAUSS_DEV_DEBUG_PORT` 只用于 source mode 调试入口，不参与实验脚本的数据库连接契约。

### 5.2 workload / scenario 的当前对应关系

当前常见场景：

- `tpcc-steady.yaml`
  - 名字保留为 TPCC steady
  - 但当前实际 runner 是 **sysbench**
- `tpcc-plus-tpch-injection.yaml`
  - 当前是 **sysbench 前台 + TPCH 注入**
- `slow-sql-under-tp.yaml`
  - 当前是 **sysbench 前台 + 慢 SQL 注入**
- `tpch-baseline.yaml`
  - 当前是纯 TPCH / AP baseline

这意味着 dashboard 标题、scenario 命名和实际 runner 语义不能混淆。

### 5.3 TPCH baseline 数据复用

`tpch-baseline.yaml` 默认已经支持 seed 复用：

- `tpch_data_policy: reuse_if_present`
- `tpch_seed_name: sf1-local`
- `dataset_profile_file: benchmarks/datasets/profiles/small-local.yaml`

语义：

1. 第一次运行生成 seed flat files 并装载数据库；
2. 后续只要 volume 和 manifest 还在，就复用已有 TPCH 数据；
3. 不需要每次重新做完整 TPCH 数据准备。

---

## 6. 当前已知限制

### 6.1 历史旧 run 仍可能带有旧格式工件

虽然 exporter 已经能兼容并过滤旧异常值，但如果你希望：

- `query-summary.tsv`
- `operator-summary.tsv`
- `top-operators-*.tsv`

这些文件本身也恢复到新标准，仍然需要对对应 `.plan` 重新执行离线分析。

### 6.2 `TPCC Run Analysis` 仍未切换到真实 BenchBase runner 工件

当前没有稳定落盘的 `tp/tpcc-run.log` 历史工件，因此 TPCC dashboard 仍不能展示真正的 BenchBase TPCC 时序指标。

不过当前 `tpcc-*` 场景的 **sysbench-derived 时序链路已经恢复并验证通过**：

- 对 fresh run `20260417-103225-tpcc-steady`，Prometheus 已实测可查询到：
  - `opengauss_run_sysbench_tps`
  - `opengauss_run_sysbench_qps`
  - `opengauss_run_sysbench_latency_p95_ms`
- 因此当前 `TPCC Run Analysis` / `Sysbench Run Analysis` 的 no-data 问题已解决；
- 当前剩余限制只在于语义层：它仍然展示的是 sysbench runner 指标，而不是 BenchBase TPCC 原生日志指标。

### 6.3 部分 session-memory 图是否有数据，仍依赖数据库视图可用性

如果 `gs_session_memory_detail` 在目标环境不可用或数据不完整，则会影响部分会话级面板的数据密度。

### 6.4 Grafana 当前消费的是聚合结果，而不是完整 operator 明细

当前 Grafana 主要消费的是：

- `query-summary.tsv`
- `operator-summary.tsv`
- `grafana-summary.json`

而不是 `operator-nodes.jsonl` 全量明细。这是为了控制基数和可视化可读性。

---

## 7. 推荐验证命令

### 7.1 快速检查 exporter 指标

```bash
curl -s http://localhost:9188/metrics | grep opengauss_plan_
curl -s http://localhost:9188/metrics | grep opengauss_run_sysbench_
curl -s http://localhost:9188/metrics | grep opengauss_run_tpch_
curl -s http://localhost:9188/metrics | grep opengauss_injection_
```

### 7.2 重新生成某次运行的离线 plan-analysis

```bash
bash scripts/benchmark/analyze-plan-batch.sh \
  --input-dir experiments/runs/<run-id>/injection/round-1 \
  --output-dir experiments/runs/<run-id>/plan-analysis/round-1
```

### 7.3 校验某次运行结果

```bash
bash scripts/experiment/validate-targets.sh --run-dir experiments/runs/<run-id>
```

### 7.4 运行典型场景

```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-steady.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/slow-sql-under-tp.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpch-baseline.yaml
```

---

## 8. 相关文件

- `README.md`
- `CLAUDE.md`
- `tools/exporter/app.py`
- `scripts/benchmark/analyze-plan-batch.py`
- `env/prometheus/prometheus.yml`
- `env/grafana/dashboards/execution-plan-analysis.json`
- `env/grafana/dashboards/opengauss-memory-overview.json`
- `env/grafana/dashboards/pressure-injection-analysis.json`
- `env/grafana/dashboards/sysbench-run-analysis.json`
- `env/grafana/dashboards/tpcc-run-analysis.json`
- `env/grafana/dashboards/tpch-run-analysis.json`
- `docs/quickstart.md`
- `docs/experiment-workflow.md`
- `docs/observability.md`
