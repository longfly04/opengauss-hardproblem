# 面向 PostgreSQL HTAP 科研的实验平台扩展与在线算子分析引擎设计

> 关联现状：
> - `docs/challenge-mapping.md`
> - `docs/observability.md`
> - `docs/pev2-batch-plan-analysis.md`
> - `scripts/experiment/run-scenario.sh`
> - `tools/exporter/app.py`
>
> 目标：把当前 openGauss + TPC 系列实验底座，扩展成一个能够同时支持更多 benchmark、支持 PostgreSQL Docker/源码实验、并为“内核级实时算子分析 + 查询驱动优化器”科研路线服务的统一平台。

---

## 1. 背景与设计目标

当前仓库已经具备三类可复用能力：

1. **容器化数据库实验底座**
   - 已支持 `stock/source` 双模式；
   - 可通过 `scripts/db/start.sh`、`scripts/db/build-source.sh` 启动或构建数据库实验环境；
   - 当前主要面向 openGauss。

2. **基于 TPC 的场景化压测与注入**
   - 已有 `sysbench`、`TPCC(BenchBase)`、`TPCH` 三条 benchmark 链路；
   - 已有 `scripts/experiment/run-scenario.sh` 场景编排入口；
   - 已能实现“TP 主负载 + AP 慢 SQL 注入”的混合场景。

3. **观测与离线分析链路**
   - 已支持会话内存、共享内存、spill/temp IO、Prometheus/Grafana；
   - 已补齐基于 PEV2 的 plan parser headless CLI，可生成 operator/query 级离线分析产物；
   - 已初步形成“实时粗粒度 + 离线细粒度”的双层证据链。

但从科研目标看，当前平台仍有三个明显边界：

- benchmark 仍主要围绕 TPC-C / TPC-H 及其变体；
- 数据库内核实验仍主要围绕 openGauss，而下一阶段研究核心将转向 PostgreSQL；
- 算子级分析仍以离线/准离线为主，尚未形成**内核内在线分析引擎 + 优化器反馈闭环**。

因此，后续平台设计要同时承载三个方向：

1. **Benchmark 扩展**：从 TPC 系列扩展到 HyBench、HTAPBench、CH-benCHmark 等更原生的混合负载；
2. **数据库内核扩展**：把当前 openGauss 实验底座抽象成可复用的数据库实验框架，并增强 PostgreSQL Docker/源码实验能力；
3. **在线分析与优化器闭环**：从会话级/离线 plan 分析，逐步走向“内核中的实时算子分析引擎”，最终驱动新型查询驱动优化器。

---

## 2. 当前底座能力盘点

## 2.1 Benchmark 编排能力

当前仓库的 benchmark 入口主要包括：

- `scripts/benchmark/run-sysbench.sh`
- `scripts/benchmark/load-tpcc.sh`
- `scripts/benchmark/run-tpcc.sh`
- `scripts/benchmark/load-tpch.sh`
- `scripts/benchmark/run-tpch.sh`
- `scripts/benchmark/inject-slow-sql.sh`
- `scripts/experiment/run-scenario.sh`

场景配置主要由以下 YAML 驱动：

- `experiments/configs/base/workloads.yaml`
- `experiments/configs/scenarios/*.yaml`
- `benchmarks/datasets/profiles/*.yaml`

这说明平台已经具备“**配置驱动 + 脚本分发 + 产物留痕**”的基本形态，适合继续抽象成 benchmark adapter 体系，而不是重写整套编排框架。

## 2.2 数据库运行时能力

当前运行时采用 Compose 分层：

- `env/compose/docker-compose.yml`：公共基座
- `env/compose/docker-compose.stock.yml`：openGauss 预构建镜像
- `env/compose/docker-compose.source.yml`：openGauss 源码编译与运行

并通过 `scripts/lib/common.sh` 抽象出：

- `compose()`
- `wait_for_db()`
- `run_gsql()`
- `run_gsql_file()`

这说明“**运行模式切换**”已经具备雏形，但当前抽象维度主要是 `stock/source`，还没有引入“数据库内核类型（openGauss / PostgreSQL）”这一维。

## 2.3 观测与分析能力

实时观测：

- SQL 视图：`sql/observability/*.sql`
- Exporter：`tools/exporter/app.py`
- Dashboard：`env/grafana/dashboards/*.json`
- 采样与快照：
  - `scripts/observe/sample-db-memory.sh`
  - `scripts/observe/snapshot-metrics.sh`
  - `scripts/observe/export-run-artifacts.sh`

离线分析：

- `docs/pev2-batch-plan-analysis.md` 已完成方案设计；
- 当前已实现基于 vendored PEV2 的 headless parser CLI；
- 可生成 `operator-nodes.jsonl`、`query-summary.tsv`、`operator-summary.tsv` 等产物。

所以后续不是从零开始，而是沿着：

> 实时系统级指标 + 离线执行计划证据 + 未来在线算子引擎

逐层演进。

---

## 3. 总体设计原则

后续整个平台扩展应遵循四条原则：

### 3.1 Benchmark 与数据库内核解耦

benchmark 不应写死为 `sysbench/tpcc/tpch`，数据库也不应写死为 `openGauss`。

平台需要演进成两层适配：

- **benchmark adapter**：定义 workload 的 prepare/load/run/cleanup/analyze 生命周期；
- **database engine adapter**：定义 openGauss / PostgreSQL 在启动、初始化、视图安装、参数模板、源码编译上的差异。

### 3.2 在线与离线分析并存

离线 plan parsing 适合：

- 算子级热点排行
- spill / temp / IO 证据
- 论文图表与实验复盘

在线分析适合：

- 当前活跃查询的内存压力判断
- admission control / runtime governor
- 优化器实时反馈

两者不应互相替代，而应形成双层分析架构。

### 3.3 先插件化，再内核化

真正把算子级实时分析嵌入 PostgreSQL 内核，是中长期工作。

更现实的路线是：

1. 先做 extension / background worker / shared memory 级插件式在线分析；
2. 验证模型、数据结构、视图接口和调度收益；
3. 再把关键能力下沉到 executor / optimizer 核心路径。

### 3.4 研究平台优先于单次脚本交付

未来工作不是再加几个脚本，而是要沉淀为：

- 可切换 benchmark
- 可切换数据库内核
- 可切换观测深度
- 可切换运行模式

的科研平台底座。

---

## 4. 方向一：扩展到 HyBench、HTAPBench 及更多混合负载 benchmark

## 4.1 当前能力的可复用基础

当前项目已经有三类 runner：

- `sysbench`：OLTP 基线
- `tpcc-runner`：BenchBase 驱动 TPCC
- `tpch-tools`：TPCH 数据与查询

且 `run-scenario.sh` 已支持：

- TP 主负载
- 注入型 AP 负载
- 场景参数化
- artifacts 导出

因此，扩展新 benchmark 的关键不是另起炉灶，而是把现有脚本体系升级成**benchmark registry + adapter dispatch**。

## 4.2 建议的 benchmark 抽象层

建议把 benchmark 统一抽象为以下接口：

```text
benchmark adapter
├─ prepare          # 镜像准备 / 二进制准备
├─ load             # schema + data load
├─ run_tp           # 事务负载
├─ run_ap           # 分析负载
├─ run_mixed        # 原生混合负载
├─ cleanup          # 数据清理
├─ collect_artifacts
└─ metric_adapter   # benchmark 原生指标 -> 平台统一指标
```

建议新增目录结构：

```text
benchmarks/
├─ registry/
│  ├─ sysbench.yaml
│  ├─ tpcc.yaml
│  ├─ tpch.yaml
│  ├─ hybench.yaml
│  ├─ htapbench.yaml
│  └─ ch-benchmark.yaml
├─ hybench/
├─ htapbench/
└─ common/
```

每个 benchmark registry 至少描述：

- benchmark 名称
- workload 类型：`tp` / `ap` / `mixed`
- load/run/cleanup 脚本路径
- 镜像名
- 依赖 schema
- 指标提取方式
- 是否支持注入型运行 / 原生 mixed 运行

## 4.3 场景模型从“TP + 注入”扩展为“多 workload 编排”

当前 `run-scenario.sh` 更偏向：

> TP workload + 可选 TPCH injection

后续应演进为：

```yaml
scenario_name: hybench-mixed-baseline
engine: postgresql
runtime_mode: stock
workloads:
  - name: tp
    benchmark: hybench
    profile: tp-heavy
    start_after_seconds: 0
  - name: ap
    benchmark: hybench
    profile: ap-windowed
    start_after_seconds: 60
  - name: refresh
    benchmark: hybench
    profile: freshness-check
    start_after_seconds: 120
```

也就是说，后续 scenario 不再只有一个 `tp_runner` 和一个 `injection_query_dir`，而是支持：

- 多 workload 列表
- 每个 workload 的 benchmark 类型
- 启停时间窗口
- 并发度、数据规模、mix ratio
- 是否共享同一 schema
- 是否需要 freshness 指标

## 4.4 HyBench / HTAPBench 的引入策略

### A. HyBench

HyBench 更适合承接“同一业务模型中的 TP + AP + Freshness”研究目标。

建议定位：

- 替代当前“TPCC + TPCH 非同构 schema 拼接”方案中的一部分实验；
- 用于研究：
  - 新鲜度（freshness）
  - TP/AP 干扰
  - mixed workload 下的内存争用
  - 查询驱动优化策略对真实 HTAP 场景的收益。

建议接入方式：

- 新增 `benchmarks/hybench/`；
- 若上游已有容器化 runner，优先适配现成 runner；
- 若没有，则封装为：
  - dataset loader
  - transaction runner
  - analytical query runner
  - freshness collector

### B. HTAPBench / CH-benCHmark / 其他混合负载

这类 benchmark 的平台价值在于：

- 更接近“同库同 schema”的 HTAP；
- 能评估事务更新与分析读取之间的竞争；
- 能暴露单纯 TPC-C + TPC-H 拼接无法覆盖的优化器与内存管理问题。

建议引入顺序：

1. `HyBench`
2. `CH-benCHmark` 或 `HTAPBench`
3. 其他更偏 cloud-native / streaming / freshness 的 benchmark

## 4.5 统一 benchmark 指标模型

为了让 Grafana / validation / compare-runs 不被 benchmark 细节绑死，建议定义统一指标层：

```text
workload_metrics
├─ throughput_tps / throughput_qps
├─ p50/p95/p99 latency
├─ abort / failure count
├─ freshness_seconds
├─ spill_bytes
├─ temp_bytes
├─ peak_session_used_bytes
├─ operator_exclusive_duration_topk
└─ operator_memory_hotspot_topk
```

也就是说：

- TPC-C 的 `tpmC`
- sysbench 的 `transactions/sec`
- HyBench 的 mixed score / freshness
- HTAPBench 的事务吞吐与分析延迟

都先映射到统一的 run summary 层，再做横向比较。

## 4.6 建议实施步骤

### Phase A1：benchmark adapter 化

- 把现有 `sysbench/tpcc/tpch` 先注册化；
- 新增统一入口，例如：
  - `scripts/benchmark/run-benchmark.sh`
  - `scripts/benchmark/load-benchmark.sh`
- `run-scenario.sh` 从硬编码切换为 dispatcher。

### Phase A2：引入 HyBench

- 新增 `benchmarks/hybench/` Docker runner；
- 定义 HyBench 的 load/run/freshness artifact 规范；
- 对接现有 observability 和 plan-analysis。

### Phase A3：引入更原生 HTAP benchmark

- 增加 `HTAPBench` / `CH-benCHmark` adapter；
- 扩展 scenario YAML，支持多 workload 原生混跑。

---

## 5. 方向二：增强 PostgreSQL 的 Docker 化实验与源码科研能力

## 5.1 目标转移：从 openGauss 验证平台到 PostgreSQL 科研底座

当前 openGauss 平台的价值主要在于：

- 已有会话内存、内存池、spill、Prometheus/Grafana 链路；
- 已有源码编译/调试型容器经验；
- 已经形成一套可复现的实验方法学。

但后续科研核心转向 PostgreSQL，因此平台需要从：

> openGauss-specific lab

演进为：

> database-engine-aware research lab

## 5.2 运行维度从 1 个变 2 个

当前运行维度主要是：

- `stock`
- `source`

后续应扩展为二维矩阵：

```text
engine x runtime_mode
├─ openGauss x stock
├─ openGauss x source
├─ PostgreSQL x stock
└─ PostgreSQL x source
```

建议在配置层新增：

- `DB_ENGINE=opengauss|postgresql`
- `DB_RUNTIME_MODE=stock|source`

而不是只靠 `OPENGAUSS_RUNTIME_MODE`。

## 5.3 建议的 Compose 分层升级

建议新增 PostgreSQL 对应的 Compose overlay：

```text
env/compose/
├─ docker-compose.yml                  # 公共服务：exporter/prometheus/grafana/benchmark runners
├─ docker-compose.opengauss.stock.yml
├─ docker-compose.opengauss.source.yml
├─ docker-compose.postgresql.stock.yml
└─ docker-compose.postgresql.source.yml
```

这样可以保留：

- benchmark runner
- exporter
- Grafana
- Prometheus

这些公共设施不变，只替换数据库服务层。

## 5.4 PostgreSQL Docker/source mode 能力建议

### A. PostgreSQL stock mode

建议提供：

- 官方 PostgreSQL 镜像作为 baseline；
- 可注入 `postgresql.conf`、`pg_hba.conf`、初始化 SQL；
- 可启用常见扩展：
  - `pg_stat_statements`
  - `auto_explain`
  - `pg_buffercache`
  - `pg_prewarm`
  - `pg_stat_kcache`（如实验环境允许）
  - `pg_wait_sampling`（如实验环境允许）

### B. PostgreSQL source mode

建议对齐 openGauss 当前的 source-mode 经验，新增：

- `postgresql-dev` 开发/编译容器；
- `postgresql` runtime 容器；
- 源码挂载、build cache、install cache；
- debug 模式（gdbserver / lldb-server）；
- 扩展与 patch 的自动重编译。

建议目录：

```text
env/postgresql/
├─ dev/
│  ├─ Dockerfile.dev
│  ├─ Dockerfile.runtime
│  ├─ dev-build.sh
│  ├─ dev-run.sh
│  └─ dev-debug.sh
└─ conf/
   ├─ postgresql.conf.template
   └─ shared_preload_libraries.conf
```

## 5.5 PostgreSQL 观测能力建议

与 openGauss 不同，PostgreSQL 侧应优先利用现成内核接口：

### 系统视图 / 扩展

- `pg_stat_activity`
- `pg_backend_memory_contexts`
- `pg_stat_database`
- `pg_stat_bgwriter`
- `pg_stat_io`（PG 16+）
- `pg_stat_statements`
- `auto_explain`
- `EXPLAIN (ANALYZE, BUFFERS, WAL, SETTINGS, FORMAT JSON/TEXT)`

### 观测策略

建议把 observability SQL 分成三层：

```text
sql/observability/
├─ common/
├─ opengauss/
└─ postgresql/
```

其中：

- `common/`：Grafana/Exporter 统一消费的抽象视图接口
- `opengauss/`：调用 `gs_*` 视图、openGauss 特有字段
- `postgresql/`：调用 `pg_*` 视图、PG 扩展字段

Exporter 则按 `DB_ENGINE` 加载不同 collector。

## 5.6 Benchmark 与 PostgreSQL 的兼容性路线

- `sysbench` 的 pgsql 驱动可直接复用；
- `BenchBase` 对 PostgreSQL 原生支持比 openGauss 更自然，可继续复用 TPCC runner；
- `TPCH` 主要依赖 schema/load/query 执行，兼容成本较低；
- HyBench/HTAPBench 后续也应优先以 PostgreSQL 为第一目标环境适配。

## 5.7 建议实施步骤

### Phase B1：引入 engine 抽象

- 将 `common.sh` 中的数据库命令抽象为：
  - `run_db_sql`
  - `run_db_file`
  - `DB_CLIENT_BIN`
  - `DB_ENGINE`
- 保持 benchmark/experiment 脚本层尽量无感。

### Phase B2：补齐 PostgreSQL stock/source

- 新增 PostgreSQL Compose overlay；
- 新增 PostgreSQL dev/runtime Dockerfiles；
- 提供 baseline + source build + debug。

### Phase B3：补齐 PostgreSQL observability

- 提供 PG 版 observability SQL、exporter collector、dashboards；
- 让同一套 dashboard 能切换 engine 对比。

---

## 6. 方向三：从离线分析走向内核中的实时算子分析引擎

## 6.1 现阶段能力定位

当前平台已经具备两类分析：

### A. 在线粗粒度

- 会话级内存
- 共享内存上下文
- spill/temp IO
- activity / query elapsed

### B. 离线细粒度

- PEV2 parser + batch orchestrator
- operator exclusive duration / exclusive cost
- sort spill / temp block / IO hotspot

这条链已经足以支持：

- 实验复盘
- 热点定位
- 参数组对比
- 论文图表生成

但还不足以支持：

- 优化器在查询规划阶段直接读取实时算子画像；
- runtime governor 依据活跃算子压力做即时调控；
- 同类查询的在线 memory bound 预测与执行中重调度。

## 6.2 目标：构建“算子级实时分析引擎”

目标不是只做一个 dashboard，而是形成三层闭环：

```text
Executor / Access Methods / Memory Manager
          ↓ 实时遥测事件
Online Operator Analysis Engine
          ↓ 聚合 / 预测 / 画像
System Views + Planner/Optimizer APIs
          ↓
Query-driven Optimizer / Runtime Governor
```

## 6.3 分阶段技术路线

### Phase C0：当前阶段（已具备）

- 外部采样 + SQL 视图 + Prometheus/Grafana
- EXPLAIN ANALYZE 离线/准离线解析
- Top-N hotspot 与 run summary

### Phase C1：插件式在线分析引擎（近期可落地）

先不直接改 PostgreSQL 核心，而是通过扩展方式验证：

#### 建议形态

- `shared_preload_libraries` 加载扩展；
- extension 创建共享内存区；
- background worker 周期聚合；
- 暴露 SQL 视图给 DBA、研究脚本与优化器原型使用。

#### 插件引擎职责

1. 采集活跃查询的基础上下文
   - `query_id`
   - `backend_id/pid`
   - `plan_node_id`
   - `node_type`
   - elapsed / rows / loops / io / temp / mem high watermark

2. 形成滑动窗口画像
   - 同类 query fingerprint 的历史算子资源画像
   - 当前活跃 query 的实时算子压力画像
   - spill 风险预测

3. 暴露系统视图
   - `lab_obs.operator_runtime_stats`
   - `lab_obs.query_memory_feedback`
   - `lab_obs.operator_spill_events`
   - `lab_obs.operator_hotspots`

#### 优点

- 研发成本较低；
- 不必马上深改 PG executor；
- 可先验证数据结构、采样频率、标签基数和视图接口。

### Phase C2：内核级实时算子分析引擎（中期研究重点）

在 PostgreSQL 内核中嵌入实时分析引擎，建议从以下路径切入：

#### A. 数据采集点

重点关注以下算子与模块：

- `nodeSort`
- `nodeHash`
- `nodeHashjoin`
- `nodeAgg`
- `nodeMaterial`
- `nodeSeqscan`
- `tuplesort`
- `hash table / batch spill`
- `BufFile` / temp file
- buffer / io instrumentation

#### B. 事件模型

建议把运行时信息抽象成事件流：

```text
operator_event
├─ ts
├─ backend_id
├─ query_id
├─ plan_id
├─ plan_node_id
├─ node_type
├─ event_type(start/end/spill/mem_peak/io)
├─ memory_bytes
├─ temp_bytes
├─ read_blocks
├─ write_blocks
├─ rows_out
└─ loops
```

#### C. 内核内存结构

建议采用：

- 每 backend 本地轻量计数结构 +
- 共享内存 ring buffer / shared hash table +
- 周期聚合 worker

避免每 tuple 或每 call 都跨进程重锁。

#### D. 视图暴露

初期建议仍暴露在扩展 schema，如：

- `lab_obs.pg_operator_runtime_stats`
- `lab_obs.pg_query_memory_budgets`
- `lab_obs.pg_operator_spill_history`

待接口稳定后，再考虑进一步内建到系统目录层。

### Phase C3：查询驱动的查询优化器（长期科研目标）

在分析引擎稳定后，优化器可利用这些在线/历史画像做决策。

#### 查询驱动优化器的核心思想

不是只基于静态成本模型，而是融合：

- 当前系统压力
- 最近一段时间同类 query 的算子画像
- 当前内存/IO/并发预算
- spill 风险与 latency SLO

从而进行更具 workload awareness 的计划选择。

#### 可驱动的决策类型

1. **工作内存 bound 决策**
   - 依据 query fingerprint + 当前活跃负载估算每 query / 每 operator 预算；
   - 对 sort/hash/agg 的 work_mem 给出动态 bound。

2. **算子选择决策**
   - 在 hash join / merge join / nested loop 之间选择；
   - 在 hash aggregate / sort aggregate 间选择；
   - 在 materialize / streaming 之间选择。

3. **并行度与 admission control**
   - 决定是否允许大查询进入；
   - 决定并行 worker 数量；
   - 决定是否延迟执行某类高风险 query。

4. **运行中动态调控**
   - 对高风险 operator 做 spill 预警；
   - 对 query group 做 memory throttling / rebalance；
   - 极端情况下做查询降级或重调度。

#### 需要新增的优化器接口

建议在研究原型阶段增加：

- `get_query_feedback(query_id / fingerprint)`
- `estimate_operator_memory_from_feedback(node_type, relids, clauses)`
- `estimate_spill_risk(...)`
- `assign_query_memory_budget(...)`

#### 建议的数据闭环

```text
历史执行画像
 + 当前系统压力
 + 当前活跃查询队列
          ↓
  Query-driven optimizer
          ↓
 动态 bound / plan selection / admission
          ↓
 执行期遥测
          ↓
 在线分析引擎回写画像
```

---

## 7. 面向当前仓库的集成设计

## 7.1 Benchmark 层改造建议

建议新增统一 dispatcher：

- `scripts/benchmark/load-benchmark.sh`
- `scripts/benchmark/run-benchmark.sh`
- `benchmarks/registry/*.yaml`

并让 `run-scenario.sh` 从：

- `tp_runner`
- `injection_query_dir`

逐步演进为：

- `engine`
- `runtime_mode`
- `workloads[]`
- `analysis_profile`
- `observability_profile`

## 7.2 数据库引擎层改造建议

建议把当前 openGauss 专属变量逐步抽象成通用字段：

- `DB_ENGINE`
- `DB_IMAGE`
- `DB_SOURCE_IMAGE`
- `DB_DEV_IMAGE`
- `DB_CLIENT_BIN`
- `DB_SOURCE_DIR`
- `DB_INSTALL_PREFIX`

保留 openGauss 的兼容变量，但新逻辑以数据库无关抽象为主。

## 7.3 观测层改造建议

建议将现有 `sql/observability` 目录拆为：

```text
sql/observability/
├─ common/
│  ├─ install_common.sql
│  └─ grant_common.sql
├─ opengauss/
└─ postgresql/
```

Exporter 则按 `DB_ENGINE` 分 collector，避免把 openGauss 与 PG 的系统视图强行揉在一起。

## 7.4 分析层改造建议

当前已具备：

- PEV2 parser headless CLI
- `scripts/benchmark/analyze-plan-batch.py`
- run 级 `plan-analysis/` 产物

后续建议分层：

### 明细层

- `operator-nodes.jsonl`
- `raw/*.plan.json`

### 汇总层

- `query-summary.tsv`
- `operator-summary.tsv`
- `grafana-summary.json`

### 在线层（未来）

- engine-specific runtime operator views
- optimizer feedback tables/views

---

## 8. 建议路线图

## P0：平台抽象重构

目标：把当前“openGauss + TPC”脚本堆叠，抽象成真正的实验平台。

- benchmark registry 化
- scenario workload 列表化
- engine/runtime_mode 双维度配置
- observability SQL 分层

## P1：PostgreSQL Docker/source 支持

目标：让 PostgreSQL 成为与 openGauss 同等级的一等实验对象。

- PostgreSQL stock/source compose overlay
- PostgreSQL dev/runtime 容器
- PostgreSQL observability views + exporter collector
- PG 版 dashboard

## P2：HyBench / HTAPBench 接入

目标：让实验从“注入式混合”升级为“原生 HTAP 混合”。

- HyBench adapter
- 更原生 mixed workload scenario
- freshness 指标接入

## P3：插件式在线算子分析引擎

目标：先把在线分析闭环跑通。

- shared_preload_libraries extension
- background worker
- shared memory telemetry
- runtime SQL views
- 在线风险画像

## P4：内核级算子分析 + 查询驱动优化器

目标：进入 PostgreSQL 内核科研主线。

- executor/operator telemetry 深改
- spill/memory feedback model
- 动态 work_mem bound
- planner/runtime governor 联动

---

## 9. 关键风险与应对

## 9.1 benchmark 引入并不只是“加 runner”

HyBench / HTAPBench 的价值在于：

- 同 schema 混合负载
- freshness
- TP/AP 干扰

所以不能只把它们当作“多一个 benchmark 容器”，而要同步升级 scenario 模型和统一指标模型。

## 9.2 PostgreSQL 与 openGauss 的观测接口差异很大

当前 openGauss 已经依赖：

- `gs_shared_memory_detail`
- `gs_session_memory_detail`

这些并不能直接迁移到 PostgreSQL。因此必须采用：

- common contract
- engine-specific collectors/views

的双层设计。

## 9.3 内核级在线分析必须严格控制 overhead

算子级实时分析最容易踩的问题是：

- 锁争用
- 共享内存放大
- 指标 cardinality 爆炸
- 执行期额外开销影响 benchmark 结果本身

所以必须遵循：

- 事件最小化
- 分层采样
- backend local + shared aggregate
- 低基数系统视图 / 高细节离线导出分离

## 9.4 不要过早把所有能力都做成 core patch

近期最合理路径仍然是：

- 先 extension/plugin 化
- 再 kernel 化
- 最后 optimizer 深度耦合

这样更适合科研迭代，也更利于发表与复现实验。

---

## 10. 最终建议

围绕用户提出的三个需求，建议把本项目定位为：

> 一个面向 PostgreSQL HTAP 内核科研的容器化实验平台，支持多 benchmark、多数据库内核、多层观测，以及从离线 plan 分析到内核级实时算子分析再到查询驱动优化器的完整演进路线。

具体落点如下：

1. **Benchmark 层**：把当前 TPC 系列能力抽象成 adapter 框架，并优先引入 HyBench；
2. **数据库层**：把 openGauss 经验沉淀为通用底座，尽快补齐 PostgreSQL stock/source Docker 实验支持；
3. **分析层**：保留当前离线 PEV2 plan analysis，作为算子证据链；
4. **在线层**：先做插件式在线分析，再下沉到 PostgreSQL 内核；
5. **优化器层**：以实时算子画像与历史反馈为基础，最终构建查询驱动的查询优化器。

这条路线既能承接当前项目已实现的能力，又能自然过渡到下一阶段 PostgreSQL 内核科研的主线。