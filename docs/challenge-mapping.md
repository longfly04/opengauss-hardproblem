# openGauss 内存难题映射与证据报告

> 关联输入：`难题.md`、`docs/openGauss内存池相关文档检索结果.md`
>
> 报告目标：把“技术诉求”映射到**当前仓库可验证能力**与**上游 openGauss 源码证据位置**，并明确当前缺口。

## 0. 适用范围与证据边界

- **仓库内（已实现）**：
  - 可复现实验编排（sysbench/TPCC + TPCH 注入）
  - SQL 观测视图、Prometheus exporter、Grafana 面板
  - run artifact 导出与验证摘要
- **仓库外（证据索引）**：
  - 上游源码目录：`/home/sducs/postgresql-dev/source_code/openGauss-server`
  - 本报告仅做“源码位置锚点”，不代表本仓库已实现对应内核改造。

---

## 1. 难题1映射：动态内存池/共享内存池自动化管理与过载保护

### 1.1 难题诉求拆解

来自 `难题.md` 的核心要求可拆为三层：

1. **池级联动**：动态内存池不足时，不能长期与共享池“冷热失衡”并存。
2. **过载抖动控制**：高并发 TP + 突发 sort/hashjoin/seqscan 注入下，将 TPS 抖动压到 10% 以内。
3. **自动化调参**：减少对资深 DBA 人工调参依赖，实现参数/策略自动调整。

### 1.2 当前仓库已具备的可观测与验证链路

#### A. 共享内存与会话内存观测

- `sql/observability/memory_pool_views.sql:12` 定义 `lab_obs.shared_memory_contexts`
- `sql/observability/memory_pool_views.sql:24` 定义 `lab_obs.shared_memory_totals`
- `sql/observability/session_memory_views.sql:21` 定义 `lab_obs.session_memory_summary`
- `sql/observability/session_memory_views.sql:32` 定义 `lab_obs.session_memory_with_activity`

这些视图为“共享内存使用/会话内存使用”提供了实时采样基础。

#### B. spill 与 temp I/O 观测

- `sql/observability/spill_views.sql:12` 定义 `lab_obs.database_spill_stats`
- `tools/exporter/app.py:33` 采集 `temp_files/temp_bytes`
- `docs/observability.md:20` 明确该链路用于落盘观测

这部分是“动态内存不足导致落盘”最直接的可验证信号。

#### C. 场景化压测与抖动验证

- `scripts/experiment/run-scenario.sh`（场景编排主入口）
- `benchmarks/tpch/variants/pressure-injection/`（慢 SQL 压力注入）
- `scripts/experiment/validate-targets.sh:73` 产出 `tps_jitter_pct`
- `scripts/experiment/validate-targets.sh:79` 产出 `peak_temp_bytes`

该链路可用于验证“突发内存压力 -> TPS 抖动/落盘变化”是否符合目标。

### 1.3 上游源码证据位置（external upstream）

#### A. 内存池与内存上限相关 GUC

- `src/common/backend/utils/misc/guc/guc_memory.cpp:230`：`memorypool_enable`
- `src/common/backend/utils/misc/guc/guc_memory.cpp:356`：`memorypool_size`
- `src/common/backend/utils/misc/guc/guc_memory.cpp:242`：`enable_memory_limit`
- `src/common/backend/utils/misc/guc/guc_memory.cpp:370`：`max_process_memory`
- `src/common/backend/utils/misc/guc/guc_memory.cpp:622`：`resilience_memory_reject_percent`
- `src/include/knl/knl_guc/knl_instance_attr_memory.h:44`：实例级内存参数结构体字段定义

#### B. 过载逃生/拒绝接入/清理连接

- `src/common/backend/utils/mmgr/mem_snapshot.cpp:716`：过载逃生主流程注释
- `src/common/backend/utils/mmgr/mem_snapshot.cpp:721`：按 `resilience_memory_reject_percent` 检查动态内存阈值
- `src/common/backend/utils/mmgr/mem_snapshot.cpp:853`：`TerminateALLConnection`
- `src/common/backend/utils/mmgr/mem_snapshot.cpp:893`：`CleanConnectionByMemory`
- `src/common/backend/utils/mmgr/mem_snapshot.cpp:898`：`rejectRequest = true`（拒绝新连接）

这证明上游已有“内存过载保护机制”，但策略偏“拒绝/清理”而非“优雅细粒度回收”。

### 1.4 当前缺口（与难题诉求对比）

- 本仓库暂无“动态池↔共享池自动再分配算法控制器”（当前是验证平台，不是自治控制器）。
- 现有可交付能力是：
  - 发现问题（抖动、spill、会话内存峰值）
  - 对比参数组（baseline/tuned）
  - 量化收益
- 仍缺“在线策略引擎”把观测信号自动转化为 GUC/配额调控动作。

---

## 2. 难题2映射：会话级 work_mem bound 精准测算与运行时调控/回收

### 2.1 难题诉求拆解

1. 基于 workload 特征精细测算每会话内存上限（bound）。
2. 随负载变化动态调整 bound。
3. 在活跃会话下优雅回收，避免 kill 带来的业务报错。

### 2.2 当前仓库可观测能力（可直接用于实验）

#### A. 会话内存与活跃状态联合观测

- `sql/observability/session_memory_views.sql:32` 的 `lab_obs.session_memory_with_activity` 已关联 `pg_stat_activity`
- `scripts/observe/sample-db-memory.sh:30` 输出 `session_used_sum_bytes/session_used_max_bytes/active_sessions/temp_bytes`
- `scripts/observe/snapshot-metrics.sh:35`、`:36`、`:38` 快照会话内存与活跃会话指标

这可用来验证“bound 策略变化前后，会话内存峰值与压力分布是否改善”。

#### B. 参数观测（当前仅配置值）

- `sql/observability/memory_pool_views.sql:38` 的 `lab_obs.selected_settings`
- 当前覆盖项见 `sql/observability/memory_pool_views.sql:51`：
  - `shared_buffers`
  - `work_mem`
  - `maintenance_work_mem`
  - `temp_buffers`
  - `max_connections`

注意：这里是 `pg_settings` 级别配置快照，不等价于“每会话运行时动态有效值”。

#### C. 算子证据（离线）

- `scripts/benchmark/run-tpch.sh:49` 采集 `EXPLAIN ANALYZE`
- `scripts/benchmark/profile-tpch.sh:71`、`:96` 解析 Hash Join/Sort/Seq Scan 等信息

可作为“算子级内存/落盘证据链”，但属于离线实验后解析，不是当前实时时序指标。

### 2.3 上游源码证据位置（external upstream）

#### A. Query memory 计算主路径

- `src/gausskernel/cbb/workload/memctl.cpp:25`：`CalculateQueryMemMain` 主入口注释
- `src/gausskernel/cbb/workload/memctl.cpp:1074`：`CalculateQueryMemMain(...)`
- `src/gausskernel/cbb/workload/memctl.cpp:936`：`AdjustQueryMem(...)`
- `src/gausskernel/cbb/workload/memctl.cpp:3334`：`AdjustMemOpConsumption(...)`
- `src/gausskernel/cbb/workload/memctl.cpp:3747`：`SetNgAssignedQueryMem(...)`

#### B. 运行时可用内存/statement_mem 协同

- `src/gausskernel/cbb/workload/dywlm_client.cpp:899`：`dywlm_client_get_memory_info(...)`
- `src/gausskernel/cbb/workload/dywlm_client.cpp:903`：`statement_mem + statement_max_mem` 参与计算
- `src/gausskernel/cbb/workload/dywlm_client.cpp:912`：优先使用 query_mem 分支
- `src/gausskernel/cbb/workload/dywlm_client.cpp:921`：与 `work_mem` 联动设定 `available_mem`

#### C. 统计侧读取 query_mem

- `src/gausskernel/cbb/workload/statctl.cpp:8426`：`WLMGetQueryMem(...)`
- `src/gausskernel/cbb/workload/statctl.cpp:8471`：`WLMGetQueryMemDN(...)`

#### D. EXPLAIN 与算子内存输出链路

- `src/include/executor/instrument.h:213`：`MemoryInfo`（含 `peakOpMemory` 等）
- `src/gausskernel/runtime/executor/nodeSort.cpp:219`：获取 sort stats
- `src/gausskernel/runtime/executor/nodeSort.cpp:226`：写入 `sorthashinfo.spaceUsed`
- `src/gausskernel/optimizer/commands/explain.cpp:4226`：输出 `Sort Method ...`
- `src/gausskernel/optimizer/commands/explain.cpp:4623`：输出 Hash `Memory Usage`
- `src/gausskernel/optimizer/commands/explain.cpp:4618`：`Peak Memory Usage`
- `src/gausskernel/optimizer/commands/explain.cpp:5344`：`Total Written Disk IO`

### 2.4 当前缺口（与难题诉求对比）

- 本仓库尚未实现“会话级 bound 预测算法”（多维负载特征建模 + 在线推断）。
- 尚未实现“活跃会话优雅回收控制器”（当前上游过载路径偏 kill/reject）。
- 目前可落地的是：
  - **观测与证据闭环**（会话内存 + spill + TPS + 离线算子证据）
  - **参数策略 A/B 对比验证框架**

---

## 3. 与 Grafana/实验方法的对应关系（现状）

### 3.1 当前实时可做

1. 会话总内存/峰值会话内存趋势（exporter + Prometheus）
2. 活跃会话数与 temp bytes 联动观察
3. shared memory 与 session memory 对照
4. 场景窗口内 TPS 抖动统计

### 3.2 当前不应过度承诺

1. **实时逐算子 work_mem 曲线**：当前链路未直接暴露为稳定实时指标。
2. **每会话实时有效 `SET LOCAL work_mem` 值**：`pg_settings` 只能保证配置面可见，不等价于完整运行时会话局部值全量透出。

---

## 4. 实验验证建议（基于现有能力）

1. 运行 `tpcc-plus-tpch-injection` 场景，固定 baseline 参数；
2. 记录 `validation-summary.tsv` 的 `tps_jitter_pct`、`peak_temp_bytes`、`peak_active_sessions`；
3. 对比不同参数组（如 `work_mem/query_mem/query_max_mem/max_process_memory`）下的指标变化；
4. 使用 `profile-tpch.sh` 的 plan 解析结果补充 Sort/Hash/SeqScan 的离线证据；
5. 形成“参数->会话内存压力->spill->TPS”的因果证据链。

---

## 5. 结论

- 本仓库已具备**难题1/难题2的验证实验室基础**：可构造压力、采集关键信号、输出对比证据。
- 上游源码中确有与“内存池参数、query memory 计算、过载保护、算子内存统计”相关的核心实现锚点。
- 但“完全自治的在线调参与优雅回收算法”当前仍是待实现能力，需在现有观测闭环之上新增控制策略模块。