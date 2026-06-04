# 基于 PEV2 的批量执行计划解析与 Grafana 集成方案

## 1. 目标

分析 `ThirdParty/pev2/` 是否可以复用其 **解析执行计划并结构化建模** 的核心逻辑，用于：

1. 对 benchmark 期间批量产生的 SQL 执行计划进行离线/准离线解析；
2. 输出半结构化、结构化数据；
3. 为 Grafana 展示以下指标提供数据基础：
   - 算子级内存占用
   - 算子级执行代价排行
   - spill / temp / I/O 热点
   - query / operator Top-N 排行

---

## 2. 结论

**结论：可行，但不建议直接“调用 Vue 组件”；建议复用 PEV2 的 `PlanService` 解析内核，封装一个 Node CLI，再由 Python/脚本批量驱动。**

更具体地说：

- `PEV2` 当前对外导出的公共 API 只有 Vue 组件 `Plan`，并没有直接导出 parser service：`ThirdParty/pev2/src/components/index.ts:1`。
- 但真正的解析核心位于 `ThirdParty/pev2/src/services/plan-service.ts:33` 的 `PlanService`，它本身**不依赖 DOM / 浏览器渲染**，可以被封装为 headless 解析器。
- `PlanService` 已支持：
  - JSON explain 输入
  - 文本 explain 输入
  - psql frame / 包裹边框清理
  - wrapped line 拼接
  - Sort / Buffers / WAL / I/O Timings / Settings / JIT / CTE / worker 信息解析
  - 计算 exclusive duration / exclusive cost / planner estimate factor / max stats
- 但它目前**不能完整满足 openGauss 算子级内存分析需求**，主要缺口是：
  1. 没有正式导出 headless parser API；
  2. 对 `Hash` 类节点常见的 `Buckets: ... Batches: ... Memory Usage: ...` 同行字段解析不完整；
  3. 对 openGauss 侧 `Peak Memory Usage`、`Total Written Disk IO` 等字段缺少专门规范化逻辑；
  4. 当前仓库 Grafana 只消费 Prometheus，尚无“计划解析结果 -> Prom 指标”的中间层。

因此，**推荐路线不是重写 parser，也不是直接从 Python 调 Vue，而是：**

> vendored PEV2 parser 增强 + Node CLI 封装 + Python 批量编排 + 结构化产物 + 低基数 Prometheus 汇总指标

---

## 3. PEV2 项目结构与核心逻辑理解

### 3.1 对外导出层只是 Vue 组件

PEV2 当前库导出仅包含：

- `ThirdParty/pev2/src/components/index.ts:1`

```ts
import Plan from "./Plan.vue"
export { Plan }
```

这说明：

- 作为 npm package 使用时，默认能力是“渲染执行计划图”；
- **没有稳定暴露 parser-only API**；
- 如果要在本仓库中复用，最好直接依赖 vendored source，或给 PEV2 增加一个 parser export/CLI entry。

### 3.2 真正的解析入口是 PlanService

核心解析器位于：

- `ThirdParty/pev2/src/services/plan-service.ts:33`

解析主入口：

- `createPlan(...)`：`ThirdParty/pev2/src/services/plan-service.ts:42`
- `fromSource(...)`：`ThirdParty/pev2/src/services/plan-service.ts:446`
- `fromJson(...)`：`ThirdParty/pev2/src/services/plan-service.ts:460`
- `fromText(...)`：`ThirdParty/pev2/src/services/plan-service.ts:566`
- `cleanupSource(...)`：`ThirdParty/pev2/src/services/plan-service.ts:407`

解析流程可概括为：

1. `fromSource()` 先做 plan 源清洗；
2. 优先尝试 JSON 解析；
3. 失败则走文本 explain parser；
4. `createPlan()` 对解析后的树做二次增强：
   - 递归处理节点
   - 计算 actual/exclusive 指标
   - 修正 CTE / InitPlan duration
   - 汇总全局最大值

### 3.3 UI 和 parser 是分层的

Vue 组件层只是调用 parser 结果做展示：

- `ThirdParty/pev2/src/store.ts:101-139`
- `ThirdParty/pev2/src/components/Plan.vue:117-145`

`store.parse()` 实际做的是：

1. `planService.fromSource(source)`
2. `planService.createPlan(...)`
3. 填充 `stats`
4. flatten tree 供 Grid / Diagram 展示

这说明：

- **解析与展示已经天然分层**；
- 完全没必要从 Python 去“驱动 Vue 组件”；
- 只要把 `PlanService` 暴露出来，就能做 headless batch parser。

---

## 4. PEV2 目前已经能提取的结构化字段

### 4.1 节点基础属性

字段定义集中在：

- `ThirdParty/pev2/src/enums.ts:59-189`
- `ThirdParty/pev2/src/interfaces.ts:72-159`

当前可建模的重点字段包括：

- `Node Type`
- `Plan Rows`
- `Plan Width`
- `Startup Cost`
- `Total Cost`
- `Actual Startup Time`
- `Actual Total Time`
- `Actual Rows`
- `Actual Loops`
- `Relation Name`
- `Index Name`
- `Join Type`
- `Parallel Aware`
- `Workers Planned` / `Workers Launched`
- `Filter`
- `Hash Cond`
- `Sort Key`
- `Presorted Key`
- `Output`
- `Settings`
- `JIT`
- `Serialization`

### 4.2 PEV2 计算出来的派生字段

在 `createPlan()` / `processNode()` / `calculateActuals()` / `calculateExclusives()` 中，PEV2 还会计算：

- `*Duration (exclusive)`：`ThirdParty/pev2/src/enums.ts:118`
- `*Cost (exclusive)`：`ThirdParty/pev2/src/enums.ts:119`
- `*Actual Rows Revised`
- `*Plan Rows Revised`
- `*Planner Row Estimate Factor`
- `*Planner Row Estimate Direction`
- 各类 `exclusive blocks`
- 各类 `exclusive io timings`
- `maxRows` / `maxCost` / `maxDuration` / `maxIo`

关键逻辑：

- `calculateActuals()`：`ThirdParty/pev2/src/services/plan-service.ts:221-274`
- `calculateExclusives()`：`ThirdParty/pev2/src/services/plan-service.ts:1344-1387`
- `calculateMaximums()`：`ThirdParty/pev2/src/services/plan-service.ts:125-217`

这对“排行型”图表非常关键，因为我们更关心 **exclusive duration / exclusive cost / spill hotspot**，而不是只看 plan root 的总值。

### 4.3 Sort / spill / buffers / I/O / WAL

已具备专门 parser：

- `parseSort()`：`ThirdParty/pev2/src/services/plan-service.ts:1044-1059`
  - 解析 `Sort Method`
  - 解析 `Memory|Disk`
  - 输出 `Sort Space Used`、`Sort Space Type`
- `parseBuffers()`：`ThirdParty/pev2/src/services/plan-service.ts:1062-1092`
- `parseWAL()`：`ThirdParty/pev2/src/services/plan-service.ts:1107-1134`
- `parseIOTimings()`：`ThirdParty/pev2/src/services/plan-service.ts:1136-1227`
- `parseSortGroups()`：`ThirdParty/pev2/src/services/plan-service.ts:1308-1341`
  - 支持 incremental sort 的 `Average Memory` / `Peak Memory`

对应测试样例也很丰富：

- `ThirdParty/pev2/src/services/__tests__/plan-service.spec.ts:214-233`
- `ThirdParty/pev2/src/services/__tests__/19-io-timings.spec.ts:1-14`
- `ThirdParty/pev2/src/services/__tests__/from-text/33-plan`
- `ThirdParty/pev2/src/services/__tests__/from-text/37-plan`

### 4.4 现有 parser 已经证明支持复杂 text explain 场景

PEV2 针对文本 explain 做了大量兼容：

- 去掉 psql / dbeaver 边框：`cleanupSource()`，`ThirdParty/pev2/src/services/plan-service.ts:407-443`
- 自动识别 JSON / text：`fromSource()`，`ThirdParty/pev2/src/services/plan-service.ts:446-458`
- 修复 line wrapping：`splitIntoLines()`，`ThirdParty/pev2/src/services/plan-service.ts:507-564`
- 支持 workers / CTE / InitPlan / Trigger / JIT / Serialization

因此，**对于当前仓库 `run-tpch.sh` 生成的 text explain 文件，它是有直接复用价值的。**

---

## 5. 当前关键缺口

### 5.1 PEV2 不是现成的 headless parser package

虽然 parser 核心可复用，但当前 package 对外只导出 Vue 组件：

- `ThirdParty/pev2/src/components/index.ts:1-3`

所以“直接在 Python 里调用 pev2 包”并不现实。需要以下两种方式之一：

1. 在 vendored source 上新增 CLI / export；
2. 在本仓库新增一个 Node wrapper，直接 import vendored source 文件。

### 5.2 Hash 节点的 Memory Usage / Buckets / Batches 解析不完整

这是最关键的限制。

openGauss / PostgreSQL 常见 Hash 节点输出类似：

```text
Buckets: 1024  Batches: 16 (originally 1)  Memory Usage: 1025kB
```

但当前 PEV2 没有 dedicated parser 处理这类“同一行多 key-value”结构。

现有 extra line fallback 位于：

- `ThirdParty/pev2/src/services/plan-service.ts:943-1025`

这段逻辑本质上只会：

- 按第一个 `: ` 拆分；
- 后面的内容整体作为 value；
- 再尝试 `parseFloat()`。

结果是：

- `Buckets` 可能被保留下来；
- `Batches` 与 `Memory Usage` 可能丢失或被降级；
- 不适合做可靠的 operator memory 分析。

这点也能从测试覆盖侧看出来：虽然测试计划文本里存在 `Buckets/Batches/Memory Usage`，但 expect 结构中并没有形成稳定字段。

### 5.3 对 openGauss 特有/更关注的字段缺少专门支持

当前目标里更关注：

- `Memory Usage`
- `Peak Memory Usage`
- `Total Written Disk IO`
- 可能的 openGauss 算子内存字段

PEV2 当前：

- 对 `Sort Method + Memory/Disk` 支持好；
- 对 incremental sort `Average/Peak Memory` 支持好；
- 对 Hash 的 `Memory Usage`、`Buckets`、`Batches` 没有完善规范化；
- 对 `Total Written Disk IO` 没有 dedicated parser；
- 对 openGauss explain 扩展字段没有专项测试覆盖。

### 5.4 当前 Grafana 链路还没有消费“计划解析结果”

本仓库现有 execution plan dashboard 只展示：

- explain query 数量
- query 持续时间

相关文件：

- `sql/observability/execution_plan_views.sql:5-31`
- `env/grafana/dashboards/execution-plan-analysis.json:31-145`

它并没有展示：

- operator exclusive duration 排行
- operator exclusive cost 排行
- sort/hash memory hotspot
- spill operator 统计

因此，必须新增一个“**批量计划解析结果 -> 结构化产物 -> Prom/Grafana**”的中间层。

---

## 6. 与当前仓库的集成点

### 6.1 计划文件已经在 benchmark 流程中生成

当前执行计划产出点：

- `scripts/benchmark/run-tpch.sh:47-55`

会在每条 SQL 运行前执行：

```bash
EXPLAIN ANALYZE $sql_content > $plan_file
```

这说明：

- 现有 benchmark 已经生成 `.plan` 文本文件；
- 不需要额外改数据库端视图，就能先做离线批量计划解析。

### 6.2 场景注入会批量生成计划文件

- `scripts/benchmark/inject-slow-sql.sh:50-57`

它会按 round 调用 `run-tpch.sh`，所以注入场景天然适合产生：

- `injection/round-1/*.plan`
- `injection/round-2/*.plan`
- ...

### 6.3 实验总入口可作为批处理挂载点

- `scripts/experiment/run-scenario.sh:70-107`

当前流程是：

1. TP 运行
2. 注入完成
3. 导出 artifacts
4. validate
5. compare

新“计划批量解析器”最合适的插入点是：

- TP / injection 全部结束后
- `export-run-artifacts.sh` 之前或之后

### 6.4 当前已有一个简陋的 plan parser，可作为替换目标

- `scripts/benchmark/profile-tpch.sh:41-167`

它当前只是靠 grep 做粗糙提取：

- `Hash Join`
- `Seq Scan`
- `Sort`
- `Aggregate`
- `Nested Loop`

局限非常明显：

- 不是树结构解析；
- 不能稳定识别 wrapped lines；
- 不能做 CTE / worker / exclusive metrics；
- 对内存字段支持很弱；
- 已存在 bash 正则问题。

**推荐新方案以 PEV2 parser 替代这条 grep 链路。**

---

## 7. 可选方案对比

### 方案 A：Python 直接重写 parser

**做法**
- 用 Python 自己解析 explain text / json
- 输出结构化 operator rows

**优点**
- 运行环境统一
- 不引入 Node subprocess

**缺点**
- 需要重写复杂 text parser
- psql frame / wrapped line / worker / CTE / IO timing / sort group 都要重做
- 维护成本高

**结论**
- 不推荐作为第一阶段方案。

### 方案 B：直接驱动 PEV2 Vue 组件

**做法**
- 试图通过浏览器/JSDOM 渲染组件后拿内部状态

**优点**
- 理论上“复用全部逻辑”

**缺点**
- 组件层有 UI 依赖
- 不是稳定 parser API
- 调用链过重

**结论**
- 不推荐。

### 方案 C：复用 PEV2 `PlanService`，封装 Node CLI，再由 Python 批量调用

**做法**
- 在 vendored PEV2 基础上新增 parser-only CLI 或 export
- Python / shell 对 benchmark 目录批量驱动 CLI
- 输出 JSONL / TSV / summary / Prom 指标源文件

**优点**
- 复用成熟 text parser
- 不需要 DOM
- 最贴近当前仓库流程
- 易于逐步增强 openGauss 特殊字段

**缺点**
- 需要一个小的 Node 包装层
- 需要给 PEV2 增加 export/CLI

**结论**
- **推荐方案**。

---

## 8. 推荐实现方案

## 8.1 总体架构

推荐新增一条“离线计划分析”链路：

```text
.run-tpch / inject-slow-sql 生成 .plan
        ↓
Node CLI (基于 PEV2 PlanService)
        ↓
结构化产物(JSON/JSONL/TSV)
        ↓
Python 汇总器 / exporter 输入
        ↓
Grafana 展示 operator Top-N / memory / cost / spill
```

### 8.2 分层职责

#### 第 1 层：PEV2 parser adapter

建议在 `ThirdParty/pev2/` 内新增 parser-only entry，例如：

- `ThirdParty/pev2/src/parser/index.ts`
- `ThirdParty/pev2/src/parser/cli.ts`

职责：

- 读取单个 plan text/json 文件
- 调用 `PlanService.fromSource()` + `createPlan()`
- 输出增强后的 plan JSON
- flatten 成 operator rows

建议同时显式导出：

- `PlanService`
- `NodeProp`
- `Node`
- `IPlanContent`

以免未来 CLI 与测试重复依赖内部私有路径。

#### 第 2 层：batch orchestrator

建议新增仓库级脚本，例如：

- `scripts/benchmark/analyze-plan-batch.py`

职责：

- 扫描一个 run 目录内的所有 `.plan`
- 调用 Node CLI 批量解析
- 聚合为 query/operator 级表
- 生成 summary / top-k / parse-errors

#### 第 3 层：artifact exporter / metrics bridge

建议新增：

- `scripts/observe/export-plan-analysis.sh` 或并入 `export-run-artifacts.sh`
- `tools/exporter/app.py` 新增“读取最新 run 的计划分析汇总文件”的能力

职责：

- 把结构化结果转换为低基数指标
- 给 Grafana 提供稳定数据源

---

## 9. 需要增强 PEV2 的解析项

### 9.1 第一阶段：先复用已有能力

第一阶段先吃下 PEV2 现成字段：

- node tree
- exclusive duration
- exclusive cost
- actual rows / loops
- planner estimate factor
- sort method / sort space used / memory vs disk
- temp/shared/local blocks
- IO timings
- WAL
- incremental sort average/peak memory

这样已经足够做：

- operator exclusive duration Top-N
- operator exclusive cost Top-N
- sort spill / temp block 热点排行
- query 级排序内存和外部排序占比

### 9.2 第二阶段：补强 openGauss / hash memory 解析

需要给 `PlanService` 增加 dedicated parser：

1. 解析 Hash 节点同行字段：

```text
Buckets: 1024  Batches: 16 (originally 1)  Memory Usage: 1025kB
```

建议拆成：

- `Hash Buckets`
- `Hash Batches`
- `Hash Original Batches`
- `Hash Memory Usage kB`

2. 解析 standalone 字段：

- `Peak Memory Usage`
- `Memory Usage`
- `Total Written Disk IO`
- `Peak Op Memory`（如果 openGauss explain 中实际存在）

3. 为 openGauss explain 样本新增 tests：

- `ThirdParty/pev2/src/services/__tests__/from-text/opengauss-*.plan`
- 对应 `-expect`

### 9.3 不建议第一阶段承诺的内容

第一阶段不建议承诺：

- 实时逐算子时序曲线
- 每个 operator 每秒 memory 样本

因为当前数据来源本质是 **每次 EXPLAIN ANALYZE 的离线 plan**，不是 executor 实时 trace。

---

## 10. 推荐输出产物设计

建议在每个 run 下新增目录：

```text
experiments/runs/<run-id>/plan-analysis/
├─ raw/
│  ├─ q1.plan.json
│  ├─ q2.plan.json
│  └─ ...
├─ operator-nodes.jsonl
├─ operator-summary.tsv
├─ query-summary.tsv
├─ top-operators-duration.tsv
├─ top-operators-cost.tsv
├─ top-operators-memory.tsv
├─ parse-errors.jsonl
└─ grafana-summary.json
```

### 10.1 `operator-nodes.jsonl`

每行一个 operator，建议字段：

- `run_id`
- `scenario_name`
- `round`
- `query_name`
- `plan_file`
- `node_id`
- `parent_node_id`
- `depth`
- `node_path`
- `node_type`
- `relation_name`
- `join_type`
- `parallel_aware`
- `workers_planned`
- `workers_launched`
- `startup_cost`
- `total_cost`
- `exclusive_cost`
- `actual_startup_time_ms`
- `actual_total_time_ms`
- `exclusive_duration_ms`
- `plan_rows`
- `actual_rows`
- `actual_rows_revised`
- `actual_loops`
- `planner_estimate_factor`
- `sort_method`
- `sort_space_type`
- `sort_space_used_kb`
- `full_sort_group_count`
- `avg_sort_space_used_kb`
- `peak_sort_space_used_kb`
- `shared_hit_blocks`
- `shared_read_blocks`
- `temp_read_blocks`
- `temp_written_blocks`
- `io_read_time_ms`
- `io_write_time_ms`
- `sum_io_read_time_ms`
- `sum_io_write_time_ms`
- `wal_records`
- `wal_bytes`
- `raw_props_json`

### 10.2 `query-summary.tsv`

每条 query 一行，建议字段：

- `query_name`
- `root_node_type`
- `plan_execution_time_ms`
- `planning_time_ms`
- `max_exclusive_duration_ms`
- `max_exclusive_cost`
- `max_sort_space_used_kb`
- `sum_temp_written_blocks`
- `sum_temp_read_blocks`
- `sum_io_read_time_ms`
- `sum_io_write_time_ms`
- `external_sort_node_count`
- `hash_spill_node_count`
- `parse_status`

### 10.3 `operator-summary.tsv`

聚合维度建议：

- `query_name + node_type`
- 或 `round + node_type`

可用于 Grafana 条形图 / TopN：

- `exclusive_duration_ms_sum`
- `exclusive_duration_ms_max`
- `exclusive_cost_sum`
- `sort_space_used_kb_max`
- `temp_written_blocks_sum`
- `io_read_time_ms_sum`

---

## 11. Grafana 集成建议

## 11.1 不建议把明细 operator 全量塞进 Prometheus label

Prometheus 不适合高基数字段。不要直接导出：

- 全量 `node_id`
- 全量 `node_path`
- 全量 `raw_query_text`

否则容易导致：

- label cardinality 过高
- Prometheus 压力上升
- dashboard 卡顿

## 11.2 推荐两级数据策略

### 明细层：文件产物

保留完整：

- `operator-nodes.jsonl`
- `raw/*.plan.json`

用于：

- 离线分析
- 二次统计
- 论文/报告产出

### 展示层：低基数 summary metrics

只导出低基数聚合指标，例如：

- `run_id`
- `query_name`
- `node_type`
- `rank`

建议暴露指标：

- `opengauss_plan_operator_exclusive_duration_ms`
- `opengauss_plan_operator_exclusive_cost`
- `opengauss_plan_operator_sort_space_used_bytes`
- `opengauss_plan_operator_temp_written_blocks`
- `opengauss_plan_operator_io_read_ms`
- `opengauss_plan_query_external_sort_count`
- `opengauss_plan_query_hash_spill_count`
- `opengauss_plan_parse_success`

## 11.3 Dashboard 建议

当前 `env/grafana/dashboards/execution-plan-analysis.json:31-145` 只有 query count / duration。

建议新增面板：

1. **Top operators by exclusive duration**
2. **Top operators by exclusive cost**
3. **Top sort memory / disk operators**
4. **Top temp written blocks by query**
5. **Query-level external sort count**
6. **Hash spill / hash memory usage summary**（二阶段）

---

## 12. 推荐实施步骤

### Phase 1：先把 PEV2 parser 跑成 headless CLI

1. 在 vendored PEV2 中新增 parser-only export / CLI；
2. 让 CLI 支持：
   - `--input-file`
   - `--input-dir`
   - `--output-dir`
   - `--format json|jsonl|tsv`
3. 先解析当前 `run-tpch.sh` 产出的 text `.plan` 文件。

### Phase 2：批量汇总与 run 目录集成

1. 新增 `scripts/benchmark/analyze-plan-batch.py`；
2. 在 `run-scenario.sh` 后段挂载该步骤；
3. 产出 `plan-analysis/` 目录。

### Phase 3：Grafana 指标桥接

1. 新增 plan summary exporter 逻辑；
2. 只导出低基数聚合指标；
3. 更新 `execution-plan-analysis.json`。

### Phase 4：openGauss 专项字段增强

1. 用真实 openGauss explain 样本补测试；
2. 增强 parser 支持：
   - Hash Memory Usage
   - Buckets / Batches
   - Peak Memory Usage
   - Total Written Disk IO
3. 再扩展 operator-level 内存图表。

---

## 13. 风险与注意事项

### 13.1 最大风险：openGauss explain 文本格式与 PostgreSQL 仍有差异

PEV2 虽然对 PostgreSQL text explain 支持很好，但 openGauss 的文本格式可能包含：

- 额外字段
- 字段同一行混排
- 输出名称差异

因此正式实现前，建议先收集一组 openGauss 样本：

- Sort / external sort
- Hash Join / Hash / spill
- Seq Scan / Aggregate / Nested Loop
- 含 `Peak Memory Usage` / `Total Written Disk IO` 的计划文本

### 13.2 当前最容易先做出的成果，不是“实时 operator telemetry”

第一阶段最现实的交付是：

- **离线批量计划解析**
- **run 级汇总与 TopN 指标**
- **Grafana 展示批次/场景级 operator hotspot**

而不是：

- 真正的 executor 运行时逐算子内存时序

### 13.3 由于 PEV2 使用 TS + alias，建议显式做一个 CLI entry

`ThirdParty/pev2/tsconfig.json:1-16` 和 `vite.config.ts:41-57` 使用了 `@/*` alias。

如果不做正式 CLI/export，而是在仓库外部直接用 Node import source file，会遇到：

- alias 解析
- TS 编译
- 模块边界

所以从工程可维护性看，**正式增加 CLI/export 是最干净的方式。**

---

## 14. 推荐最终方案

**推荐最终方案：**

1. **增强 vendored PEV2**：把 `PlanService` 暴露为 parser-only API，并补充 openGauss/hash memory 解析；
2. **新增 Node CLI**：做批量计划解析；
3. **新增 Python orchestrator**：扫描 benchmark/run 目录并汇总；
4. **输出双层产物**：
   - 明细 JSONL / raw JSON
   - 低基数 summary metrics
5. **Grafana 只展示聚合/排行结果**，不直接吃全量 operator 明细。

这条路线：

- 复用现有第三方成熟 parser；
- 对当前仓库改动最小；
- 能较快把 `profile-tpch.sh` 的粗糙 grep 分析升级为结构化 plan analysis；
- 也为后续 openGauss 特定字段扩展保留空间。

---

## 15. 落地优先级建议

### P0
- 让 PEV2 parser headless 可调用
- 批量解析 `.plan`
- 产出 `operator-nodes.jsonl` / `query-summary.tsv`

### P1
- 对接 `run-scenario.sh`
- 生成 plan-analysis artifacts
- 更新 execution-plan dashboard 展示 TopN

### P2
- 增强 hash/openGauss memory 字段
- 支持 `Peak Memory Usage` / `Total Written Disk IO`

### P3
- 如果后续确有需要，再考虑把更细粒度计划分析结果导入专门分析存储（而不是 Prometheus）

---

## 16. 可直接执行的下一步

如果进入实现阶段，建议按以下顺序推进：

1. 在 `ThirdParty/pev2/` 增加 parser CLI；
2. 先拿 `scripts/benchmark/run-tpch.sh` 产生的 `.plan` 目录做单次批量解析；
3. 定稿 `operator-nodes.jsonl` / `query-summary.tsv` schema；
4. 再决定 exporter/Grafana 的汇总指标集合。
