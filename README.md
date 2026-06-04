# openGauss memory experiment lab

本仓库提供一套 **Docker 优先、Linux 兼容** 的 openGauss 实验环境，用于围绕 [难题.md](难题.md) 中的内存管理、work\_mem / memory pool 观测、执行计划离线分析和内核实验做部署、压测、观测、对比与源码调试。

当前仓库已经形成两条可切换、但共享同一套 benchmark / observability / experiment 脚本的运行通道：

- **stock mode**：使用 **本地源码编译后打包出的可信 baseline 镜像** 运行 openGauss，适合做稳定基线、回归对比和重复实验。
- **source mode**：在容器内挂载 openGauss 源码与 third\_party，编译、调试、反复修改内核代码，并继续跑同一套实验流程。

同时，仓库已经支持把 benchmark 运行过程中的数据库指标、runner 日志、离线执行计划分析结果统一接入同一个 exporter：

- 用户入口仍然是 **shell 脚本**；
- shell 调用 **Python 批处理脚本**；
- Python 调用 vendored **PEV2 Node CLI parser**；
- 聚合结果落盘到 `experiments/runs/.../plan-analysis/...`；
- `tools/exporter/app.py` 统一读取 `lab_obs.*` SQL 视图和 `experiments/runs/...` 工件，并暴露给 Prometheus / Grafana。

***

## 1. 本轮最新更新摘要

本轮主要更新有 5 类：

### 1.1 执行计划异常值修复

已修复 openGauss text plan 在 loops 极大时导致的离线时长异常放大问题：

- PEV2 text plan duration 计算增加了 plan footer runtime sanity 约束；
- `analyze-plan-batch.py` 不再盲目用 `max(actual_total_time_ms)` 推导 query runtime；
- 新增 query 级质量字段：
  - `runtime_source`
  - `duration_sanity_status`
  - `invalid_operator_count`
- exporter 会暴露：
  - `opengauss_plan_query_duration_sanity_ok`
  - `opengauss_plan_query_invalid_operator_count`
  - `opengauss_plan_analysis_invalid_rows_total`

因此，Grafana 不再把“上千年”的 query / operator duration 直接画进主图。

### 1.2 exporter 已统一收敛

`tools/exporter/app.py` 现在是唯一 exporter，统一暴露：

- 实时 DB 指标：
  - `opengauss_shared_*`
  - `opengauss_session_*`
  - `opengauss_temp_*`
  - `opengauss_setting_*`
- run artifact 指标：
  - `validation-summary.tsv` → `opengauss_run_validation_metric`
  - `tp/sysbench-run.log` → `opengauss_run_sysbench_*`
  - `tp/tpch/*.plan` / `plan-analysis/tpch/*` → `opengauss_run_tpch_query_*`、`opengauss_tpch_run_*`
  - `plan-analysis/*` → `opengauss_plan_*`
  - `injection/round-*` → `opengauss_injection_*`

Prometheus 中原来孤立的 `sysbench_log_exporter` 抓取项已删除。

### 1.3 6 组 Grafana dashboard 已重定义职责

当前 `openGauss Lab` 下的 6 组 dashboard 语义如下：

- **openGauss Memory Overview**
  - 实时共享池 / 会话池 / temp IO / 关键参数总览
- **Execution Plan Analysis**
  - 离线 query / operator 证据 + 数据质量面板
- **Pressure Injection Analysis**
  - 注入 query 证据 + 前台 TPS / latency / QPS 退化
- **Sysbench Run Analysis**
  - 真实 sysbench runner 日志逐秒指标
- **TPCC Run Analysis**
  - 当前阶段展示 **TPCC 命名场景下的 sysbench runner 指标**
- **TPCH Run Analysis**
  - TPCH query 维度 duration / spill / operator hotspot 分析

### 1.4 历史 run 兼容性增强

当前 exporter 已兼容两类旧工件问题：

1. **旧 TPCH run 缺少** **`tp/tpch/summary.tsv`**
   - 会回退到 `plan-analysis/tpch/query-summary.tsv` 以及 `tp/tpch/*.plan/*.log`
2. **旧 plan-analysis 工件仍包含异常 duration**
   - exporter 会标记为 flagged query，并从主 Top-N 图中排除

如果你希望把旧 run 的工件文件本身也修正到新格式，仍建议对对应 `.plan` 重新执行离线分析。

### 1.5 source / stock 启停链路已验证打通

本轮已完成对双运行模式整条链路的回归验证：

- `bash scripts/db/build-source.sh` 可成功构建 `opengauss-dev` 与 source runtime；
- `bash scripts/db/build-source.sh --emit-stock-image` 可成功生成 trusted stock baseline image；
- `bash scripts/db/start.sh --mode source --full-observability` 与 `bash scripts/db/start.sh --mode stock --full-observability` 均已验证可健康启动；
- 启动后 bootstrap SQL、observability 视图安装与 `select 1` 基本连通性检查均通过。

为打通这条链路，本轮同时修正了几类关键运行时问题：

- source runtime / `opengauss-dev` 调试端口已拆分，数据库业务端口仍保持统一；
- runtime image 已补齐 openGauss 所需 third_party 运行时动态库；
- runtime image 已补齐 locale 支持，兼容历史 `en_US.utf8` 数据目录；
- source mode 启动时会兼容两类历史数据目录布局：
  - `${OPENGAUSS_DATA_DIR}`
  - `${OPENGAUSS_DATA_DIR}/data`

### 1.6 本轮回归修复已完成闭环验证

用户此前报告的 3 个关键回归，目前都已经完成修复并通过实跑验证：

1. `tpcc-steady.yaml` 的 sysbench 时序链路已恢复
   - `tools/exporter/app.py` 已修复 shared-memory context 重复 label 导致的 scrape 污染；
   - sysbench 工件导出只保留近期 run，避免历史显式时间戳持续污染当前 Prometheus；
   - 在重建 Prometheus 数据卷后，重新运行 `20260417-103225-tpcc-steady`，已确认可以从 Prometheus 查询到：
     - `opengauss_run_sysbench_tps`
     - `opengauss_run_sysbench_qps`
     - `opengauss_run_sysbench_latency_p95_ms`
   - 该 run 的 3 组时序都已验证存在 301 个采样点，因此 `Sysbench Run Analysis` 与 `TPCC Run Analysis` 当前的 sysbench-derived 面板已经恢复出图条件。

2. `tpch-baseline.yaml` 的 TPCH seed 复用路径已恢复
   - `scripts/benchmark/load-tpch.sh` 已改为 `pg_class + pg_namespace` existence-check；
   - 不再调用 openGauss 不兼容的 `to_regclass()`；
   - `20260416-224450-tpch-baseline` 已验证能直接复用已有 TPCH seed，不再报 `function to_regclass(unknown) does not exist`。

3. stock mode 已稳定切回本地 trusted baseline image
   - `scripts/lib/common.sh` 会把 legacy `OPENGAUSS_IMAGE` 远端 tag 自动归一化到 `local/opengauss-stock-baseline:latest`；
   - `bash scripts/db/start.sh --mode stock` 在本地 baseline image 缺失时会自动触发源码编译并生成 trusted stock image；
   - 实跑中，`oglab-opengauss` 已确认运行在 `local/opengauss-stock-baseline:latest`，而不是历史远端镜像。

***

## 2. 仓库目录

- [env/](env/)：Compose、openGauss 容器、Prometheus、Grafana、runtime Dockerfile。
- [benchmarks/](benchmarks/)：sysbench、TPCC、TPCH runner 与 SQL 查询集。
- [experiments/](experiments/)：场景配置、硬件 profile、历史运行产物。
- [scripts/](scripts/)：数据库启动、benchmark、观测、实验编排脚本。
- [sql/](sql/)：观测视图、参数 preset、初始化 SQL。
- [tools/exporter/](tools/exporter/)：统一 Prometheus exporter。
- [ThirdParty/pev2/](ThirdParty/pev2/)：vendored PEV2，已扩展 headless parser / CLI 能力。
- [docs/](docs/)：架构说明、实验流程、观测能力、批量执行计划分析设计等文档。

***

## 3. 核心能力总览

### 3.1 双运行模式

#### stock mode

- 用于可信 baseline。
- 默认镜像标签见 [env/compose/.env.example](env/compose/.env.example)：
  - `OPENGAUSS_IMAGE=local/opengauss-stock-baseline:latest`
- 该镜像不再依赖第三方 openGauss 镜像来源，而是由本仓库的源码编译流程生成。
- 如果本地还没有这个镜像，`scripts/db/start.sh --mode stock` 会自动触发源码编译并打包 trusted stock image。
- 一旦镜像构建完成，后续 stock 启动可直接复用，不需要每次重新编译。

#### source mode

- 用于源码开发、断点调试、改内核、反复构建。
- `scripts/db/start.sh --mode source` 启动前会先执行 `scripts/db/build-source.sh`。
- 运行时仍保留编译缓存 / install cache volume，适合频繁开发迭代。
- 可结合 `scripts/db/dev-shell.sh`、`scripts/db/start-debug.sh` 使用。

### 3.2 Benchmark 与场景编排

支持：

- sysbench
- TPCC
- TPCH
- TP 工作负载 + 注入式慢 SQL / TPCH 查询

统一入口：

- 单独 benchmark：`scripts/benchmark/*.sh`
- 端到端场景：`scripts/experiment/run-scenario.sh`

当前场景语义需要注意：

- `tpcc-steady.yaml` 当前实际 runner 是 **sysbench**；
- `tpcc-plus-tpch-injection.yaml` 当前是 **sysbench 前台 + TPCH 注入**；
- `run-tpcc.sh` 仍保留为 BenchBase-backed TPCC 能力，但仓库中尚无稳定的 `tp/tpcc-run.log` 历史工件；
- 不过 `tpcc-*` 场景当前依赖的 `opengauss_run_sysbench_*` 时序已经完成回归验证，fresh run `20260417-103225-tpcc-steady` 已确认可在 Prometheus 中查询到 TPS/QPS/P95 指标。

### 3.3 可观测能力

仓库会自动安装 SQL 观测视图，并通过统一 exporter 暴露给 Prometheus / Grafana：

- 共享内存、内存池、关键参数
- 会话级内存变化
- temp file / spill / IO
- 执行计划统计
- 离线 plan-analysis 的 query / operator 聚合指标
- validation summary 指标
- sysbench 逐秒指标
- TPCH query 级指标
- injection round/query 指标

### 3.4 离线执行计划分析

当前已经支持对一批 `.plan` 文件做离线分析，并输出：

- `operator-nodes.jsonl`
- `query-summary.tsv`
- `operator-summary.tsv`
- `top-operators-duration.tsv`
- `top-operators-cost.tsv`
- `top-operators-memory.tsv`
- `grafana-summary.json`

Grafana 通过 exporter 消费的是这些 **低基数聚合结果**，而不是 `operator-nodes.jsonl` 明细。

此外，query / operator 数据质量现在也被显式输出和可视化：

- `duration_sanity_status`
- `invalid_operator_count`
- `opengauss_plan_query_duration_sanity_ok`
- `opengauss_plan_query_invalid_operator_count`
- `opengauss_plan_analysis_invalid_rows_total`

***

## 4. 环境准备

### 4.1 检查依赖

```bash
bash scripts/bootstrap/check-prereqs.sh
```

### 4.2 初始化本地环境文件

```bash
bash scripts/bootstrap/init-env.sh
```

该脚本会在缺失时创建：

- `env/compose/.env`

并准备本地输出目录。

### 4.3 关键环境变量

主要配置位于：

- [env/compose/.env.example](env/compose/.env.example)
- 本地实际生效文件：`env/compose/.env`

重点变量：

- `OPENGAUSS_RUNTIME_MODE=stock|source`
- `OPENGAUSS_IMAGE=local/opengauss-stock-baseline:latest`
- `OPENGAUSS_SOURCE_IMAGE=local/opengauss-source-runtime:latest`
- `OPENGAUSS_DEV_IMAGE=local/opengauss-source-dev:latest`
- `OPENGAUSS_SOURCE_DIR=./ThirdParty/openGauss-server`
- `OPENGAUSS_BINARYLIBS_DIR=./ThirdParty/openGauss-binarylibs`
- `DB_PORT=5432`
- `PROMETHEUS_PORT=9090`
- `GRAFANA_PORT=3000`
- `OG_MEMORY_EXPORTER_PORT=9188`
- `OPENGAUSS_DEBUG_PORT=2345`（source runtime / `opengauss` 服务调试端口）
- `OPENGAUSS_DEV_DEBUG_PORT=2346`（`opengauss-dev` 开发容器调试端口）

如果要启用 source mode，必须确保：

- `OPENGAUSS_SOURCE_DIR` 指向包含 upstream `build.sh` 的 openGauss 源码根目录；
- `OPENGAUSS_BINARYLIBS_DIR` 指向解压后的 `binarylibs` 根目录；
- `binarylibs` 根目录至少包含 `buildtools/`、`kernel/platform/`、`kernel/dependency/`；
- 当前仓库默认按 upstream README 的约定，以 **openEuler 24.03 x86\_64 + gcc10.3 binarylibs** 进行 source build。

***

## 5. 快速开始

### 5.1 首次准备可信 stock 基座

```bash
bash scripts/bootstrap/check-prereqs.sh
bash scripts/bootstrap/init-env.sh
bash scripts/bootstrap/prepare-images.sh --include-db-source
```

这一步会：

1. 构建 exporter / TPCC / TPCH 辅助镜像；
2. 构建 `opengauss-dev`；
3. 在 dev 容器内按 upstream `README.md` 的方式执行 `./build.sh -m <type> -3rd <binarylibs-root>`；
4. 使用 upstream 实际产出的 `mppdb_temp_install/` 作为 install tree 来源；
5. 构建 source runtime；
6. 将 install tree stage 到 `env/opengauss/build-context/install/`；
7. 打包出可信 stock baseline image（默认标签为 `local/opengauss-stock-baseline:latest`）。

### 5.2 启动 stock mode

```bash
bash scripts/db/start.sh --mode stock --full-observability
```

### 5.3 启动 source mode

```bash
bash scripts/db/start.sh --mode source --full-observability
```

### 5.4 默认访问地址

默认示例地址如下，实际端口以 `env/compose/.env` 为准：

- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`
- Exporter metrics: `http://localhost:9188/metrics`

Grafana 默认账号密码见 [env/compose/docker-compose.yml](env/compose/docker-compose.yml)：

- 用户名：`admin`
- 密码：`admin`

### 5.5 stock / source 快速切换

当前两种模式已经按同一套 `DB_PORT` 契约完成验证，因此 benchmark / experiment 脚本不需要因为模式切换而改数据库端口。

需要切换时，直接先停止当前模式，再启动另一种模式即可：

```bash
bash scripts/db/stop.sh --mode stock --full-observability
bash scripts/db/start.sh --mode source --full-observability

bash scripts/db/stop.sh --mode source --full-observability
bash scripts/db/start.sh --mode stock --full-observability
```

注意：

- source runtime 调试端口使用 `OPENGAUSS_DEBUG_PORT`；
- `opengauss-dev` 开发容器调试端口使用 `OPENGAUSS_DEV_DEBUG_PORT`；
- 在同一个 `COMPOSE_PROJECT_NAME` 下，`stock` 与 `source` 仍应作为“二选一”的运行模式，而不是同时并行启动的两套数据库。

***

## 6. 常用命令

### 6.1 启动 / 停止 / 重置

```bash
bash scripts/db/start.sh --mode stock --full-observability
bash scripts/db/start.sh --mode source --full-observability

bash scripts/db/stop.sh --mode stock --full-observability
bash scripts/db/stop.sh --mode source --full-observability

bash scripts/db/reset.sh --mode stock
bash scripts/db/reset.sh --mode source
```

### 6.2 源码开发

```bash
bash scripts/db/build-source.sh
bash scripts/db/dev-shell.sh
bash scripts/db/start-debug.sh
```

其中 `build-source.sh` 会先校验：

- source root 是否包含 upstream `build.sh`；
- `OPENGAUSS_BINARYLIBS_DIR` 是否是解压后的 binarylibs 根目录；
- binarylibs 根目录是否至少包含 `buildtools/`、`kernel/platform/`、`kernel/dependency/`。

自动编译默认走 upstream `build.sh` 的 make/configure 路径，不主动切换到 `--cmake`。

### 6.3 生成 trusted stock baseline image

```bash
bash scripts/db/build-source.sh --emit-stock-image
```

***

## 7. Benchmark 使用指南

### 7.1 sysbench

准备数据：

```bash
bash scripts/benchmark/run-sysbench.sh \
  --mode prepare \
  --tables 8 \
  --table-size 50000 \
  --threads 64 \
  --time 30
```

运行压测：

```bash
bash scripts/benchmark/run-sysbench.sh \
  --mode run \
  --tables 8 \
  --table-size 50000 \
  --threads 64 \
  --time 180 \
  --report-interval 1
```

### 7.2 TPCC

加载数据：

```bash
bash scripts/benchmark/load-tpcc.sh --scalefactor 10 --terminals 32 --duration 300
```

运行压测：

```bash
bash scripts/benchmark/run-tpcc.sh --scalefactor 10 --terminals 32 --duration 300
```

### 7.3 TPCH

加载数据：

```bash
bash scripts/benchmark/load-tpch.sh --scale-factor 1
```

运行单条查询：

```bash
bash scripts/benchmark/run-tpch.sh --query-file benchmarks/tpch/variants/spill-prone/<query>.sql
```

运行一组查询：

```bash
bash scripts/benchmark/run-tpch.sh --query-dir benchmarks/tpch/variants/spill-prone
```

***

## 8. 离线执行计划分析指南

### 8.1 入口关系

固定链路如下：

```bash
scripts/benchmark/analyze-plan-batch.sh
-> python: scripts/benchmark/analyze-plan-batch.py
  -> node: ThirdParty/pev2 npm run parse-plan
```

### 8.2 直接分析一批 `.plan`

```bash
bash scripts/benchmark/analyze-plan-batch.sh \
  --input-dir experiments/reports/tpch-profile \
  --output-dir experiments/reports/tpch-profile/plan-analysis \
  --analysis-name tpch-profile
```

如果是某次运行目录中的注入计划，也可以显式补充标签：

```bash
bash scripts/benchmark/analyze-plan-batch.sh \
  --input-dir experiments/runs/<run-id>/injection/<round> \
  --output-dir experiments/runs/<run-id>/plan-analysis/<round> \
  --analysis-name <round> \
  --run-id <run-id> \
  --scenario-name <scenario-name>
```

### 8.3 场景运行中的自动分析

`bash scripts/experiment/run-scenario.sh ...` 已内置自动分析逻辑：

- 注入式查询执行后，如果 `injection/<round>/` 下存在 `.plan`；
- 脚本会自动调用 `scripts/benchmark/analyze-plan-batch.sh`；
- 并把结果写入 `experiments/runs/<run-id>/plan-analysis/<analysis-name>/`。

### 8.4 离线分析产物说明

每个分析目录通常包含：

```text
operator-nodes.jsonl
query-summary.tsv
operator-summary.tsv
top-operators-duration.tsv
top-operators-cost.tsv
top-operators-memory.tsv
grafana-summary.json
```

### 8.5 当前 exporter 暴露的核心 plan-analysis 指标

- `opengauss_plan_analysis_plan_count`
- `opengauss_plan_analysis_query_count`
- `opengauss_plan_analysis_operator_count`
- `opengauss_plan_analysis_invalid_rows_total`
- `opengauss_plan_query_execution_time_ms`
- `opengauss_plan_query_duration_sanity_ok`
- `opengauss_plan_query_invalid_operator_count`
- `opengauss_plan_query_max_exclusive_duration_ms`
- `opengauss_plan_query_max_exclusive_cost`
- `opengauss_plan_query_temp_written_blocks`
- `opengauss_plan_query_external_sort_nodes`
- `opengauss_plan_operator_exclusive_duration_ms_sum`
- `opengauss_plan_operator_exclusive_cost_sum`
- `opengauss_plan_operator_sort_space_used_kb_max`
- `opengauss_plan_operator_temp_written_blocks_sum`

默认标签包括：

- `run`
- `scenario`
- `analysis`
- `query_name`
- `node_type`

***

## 9. 场景实验指南

统一入口：

```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-steady.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/slow-sql-under-tp.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpch-baseline.yaml
```

### 9.1 `run-scenario.sh` 做了什么

`scripts/experiment/run-scenario.sh` 会自动完成：

1. 加载基础配置与 scenario YAML；
2. 启动数据库栈；
3. 准备 TP 负载数据（sysbench 或 TPCC）；
4. 按需加载 TPCH 数据；
5. 后台采样数据库内存；
6. 并行运行 TP 负载与注入式慢 SQL；
7. 若生成 `.plan`，自动做离线执行计划分析；
8. 导出 artifacts；
9. 生成验证与对比结果。

### 9.2 结果目录

每次运行都会在 [experiments/runs/](experiments/runs/) 下生成独立目录：

```text
experiments/runs/<timestamp>-<scenario>/
```

典型内容包括：

- `tp/sysbench-run.log`
- `tp/tpch/*.log`
- `tp/tpch/*.plan`
- `tp/tpch/summary.tsv`（旧 run 可能缺失）
- `injection/round-*`
- `observability/db-memory.tsv`
- `run-summary.env`
- `validation-summary.tsv`
- `comparison.md`
- `plan-analysis/<analysis-name>/...`

### 9.3 旧 run 兼容说明

当前 exporter 对旧工件的兼容策略：

- 旧 TPCH run 缺 `summary.tsv`：回退到 `plan-analysis/tpch/query-summary.tsv` 和 `tp/tpch/*.plan/*.log`
- 旧 plan-analysis 仍有异常时长：通过 quality 指标标记为 flagged，并在主 dashboard Top-N 中排除

如果需要把旧 run 的工件本身修正到新标准，建议重新执行离线 plan-analysis。

***

## 10. Grafana / Prometheus 使用指南

### 10.1 当前主要 dashboard

- [env/grafana/dashboards/opengauss-memory-overview.json](env/grafana/dashboards/opengauss-memory-overview.json)
- [env/grafana/dashboards/execution-plan-analysis.json](env/grafana/dashboards/execution-plan-analysis.json)
- [env/grafana/dashboards/pressure-injection-analysis.json](env/grafana/dashboards/pressure-injection-analysis.json)
- [env/grafana/dashboards/sysbench-run-analysis.json](env/grafana/dashboards/sysbench-run-analysis.json)
- [env/grafana/dashboards/tpcc-run-analysis.json](env/grafana/dashboards/tpcc-run-analysis.json)
- [env/grafana/dashboards/tpch-run-analysis.json](env/grafana/dashboards/tpch-run-analysis.json)

### 10.2 6 组 dashboard 各自回答什么问题

#### openGauss Memory Overview

回答：当前数据库共享池、会话池、temp IO 和关键参数处于什么状态。

#### Execution Plan Analysis

回答：哪些 query / operator 最慢、最会 spill、哪些 plan 结果存在质量问题。

#### Pressure Injection Analysis

回答：注入了什么查询、哪一轮最重、对前台 TPS / latency 造成了什么退化。

#### Sysbench Run Analysis

回答：真实 sysbench 运行期间 TPS / QPS / latency / err/s / reconn/s 如何变化。

#### TPCC Run Analysis

回答：当前 TPCC 命名场景下的 runner 指标如何变化。

注意：当前它展示的是 **sysbench runner 日志指标**，不是 BenchBase TPCC 原生日志指标。

#### TPCH Run Analysis

回答：哪些 TPCH query 慢、哪些 spill、哪些 operator 最重。

### 10.3 exporter 指标快速检查

```bash
curl -s http://localhost:9188/metrics | grep opengauss_plan_
curl -s http://localhost:9188/metrics | grep opengauss_run_sysbench_
curl -s http://localhost:9188/metrics | grep opengauss_run_tpch_
curl -s http://localhost:9188/metrics | grep opengauss_injection_
```

***

## 11. 常见工作流

### 工作流 A：做一次可信 baseline 实验

```bash
bash scripts/bootstrap/init-env.sh
bash scripts/bootstrap/prepare-images.sh --include-db-source
bash scripts/db/start.sh --mode stock --full-observability
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-steady.yaml
```

### 工作流 B：修改源码并重新验证

```bash
bash scripts/db/dev-shell.sh
# 在容器内修改 / 编译
bash scripts/db/start.sh --mode source --full-observability
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/slow-sql-under-tp.yaml
```

### 工作流 C：分析一批历史 `.plan`

```bash
bash scripts/benchmark/analyze-plan-batch.sh \
  --input-dir <plan-dir> \
  --output-dir <analysis-dir> \
  --analysis-name <analysis-name>
```

### 工作流 D：验证 Grafana 的 query/operator 证据链

1. 跑完 scenario 或 TPCH profile；
2. 确认 `experiments/runs/.../plan-analysis/...` 已生成；
3. 确认 exporter 正在暴露 `opengauss_plan_*` 指标；
4. 打开 Grafana 的 `Execution Plan Analysis`、`TPCH Run Analysis` 或 `Pressure Injection Analysis` dashboard。

***

## 12. 相关文档

建议配合阅读：

- [docs/latest-capabilities.md](docs/latest-capabilities.md)
- [docs/quickstart.md](docs/quickstart.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/experiment-workflow.md](docs/experiment-workflow.md)
- [docs/source-build.md](docs/source-build.md)
- [docs/debugging.md](docs/debugging.md)
- [docs/dev-workflow.md](docs/dev-workflow.md)
- [docs/observability.md](docs/observability.md)
- [docs/pev2-batch-plan-analysis.md](docs/pev2-batch-plan-analysis.md)
- [docs/challenge-mapping.md](docs/challenge-mapping.md)
- [docs/challenge-evidence-index.md](docs/challenge-evidence-index.md)
- [docs/postgresql-htap-research-roadmap.md](docs/postgresql-htap-research-roadmap.md)
- [docs/bare-metal-notes.md](docs/bare-metal-notes.md)

***

## 13. 当前实现约束与说明

- `stock` 与 `source` 仍是仓库唯一的两种运行语义，没有引入第三种模式。
- `stock` 现在代表“源码编译后打包出的可信 baseline 镜像”。
- `source` 仍代表“挂载源码、保留开发缓存、适合调试”的模式。
- 当前已经验证 `bash scripts/db/start.sh --mode source --full-observability` 与 `bash scripts/db/start.sh --mode stock --full-observability` 都能完成健康检查、bootstrap SQL 和 observability 安装。
- source mode 会自动兼容历史 volume 中的 `${OPENGAUSS_DATA_DIR}/data` 布局。
- runtime / stock image 当前已打包 source build 运行所需的 third_party 动态库和 locale 支持，可兼容历史 `en_US.utf8` 集群。
- `stock` 与 `source` 共用同一个 `DB_PORT`；如果要切换模式，先 stop 当前模式，再 start 另一模式，不建议在同一个 Compose project 下同时并行启动。
- `tpcc-steady` / `tpcc-plus-tpch-injection` 当前仍是 **sysbench 驱动场景**。
- `run-tpcc.sh` 仍保留为 BenchBase-backed TPCC 能力，但当前 Grafana 尚未接入稳定的 `tp/tpcc-run.log` 历史工件。
- Grafana 当前消费的是 plan-analysis 聚合结果，而不是原始 `operator-nodes.jsonl` 明细。
- 历史旧 run 可能缺少 `tp/tpch/summary.tsv`；当前 exporter 已兼容 fallback。
- 历史旧 run 可能保留修复前的异常 query/operator duration；当前 exporter 会通过质量指标标记并过滤，但如果你需要把工件本身修正，请重新执行离线分析。
- 如果你修改了 openGauss 源码并希望更新 baseline，需要重新执行：

```bash
bash scripts/db/build-source.sh --emit-stock-image
```

- 如果只是想验证源码改动，不需要重新生成 baseline，则直接用：

```bash
bash scripts/db/start.sh --mode source --full-observability
```

