# Quickstart

本文档按**最容易上手**的方式，带你走完本项目的完整实验流程：

1. 检查环境并初始化配置；
2. 准备可信的 openGauss 基座镜像；
3. 启动实验环境；
4. 跑一次 benchmark / scenario；
5. 在 Grafana 中观测；
6. 查看 artifacts 并做结果验证；
7. 如有需要，切到 source mode 继续改源码和复现实验。

如果你是第一次使用，建议直接按本文档从上往下执行一遍。

---

## 1. 先理解两个运行模式

本仓库只有两种运行模式：

| 模式 | 适合什么场景 | 特点 |
| --- | --- | --- |
| `stock` | 做稳定 baseline、回归对比 | 使用**本仓库源码编译后打包出的 trusted baseline image** |
| `source` | 改 openGauss 内核、反复编译调试 | 挂载 `ThirdParty/openGauss-server` 与 `ThirdParty/openGauss-binarylibs`，编译后继续跑同一套实验流程 |

记住两个关键点：

- `stock` 和 `source` **共用同一个 `DB_PORT`**，所以 benchmark / experiment 脚本不需要因为模式切换而改数据库端口；
- source mode 只有调试入口端口单独拆分：
  - `OPENGAUSS_DEBUG_PORT`：source runtime 中 `gaussdb` 的调试端口
  - `OPENGAUSS_DEV_DEBUG_PORT`：`opengauss-dev` 开发容器调试端口

---

## 2. 使用前准备

### 2.1 基础依赖

至少需要：

- Linux 或可运行 Linux 容器的 Docker 主机
- Docker
- Docker Compose plugin 或 `docker-compose`
- bash

先检查依赖：

```bash
bash scripts/bootstrap/check-prereqs.sh
```

### 2.2 初始化本地配置

```bash
bash scripts/bootstrap/init-env.sh
```

这一步会：

- 在缺失时创建 `env/compose/.env`
- 准备本地输出目录

### 2.3 source build 需要的源码与 binarylibs

如果你要使用以下任一命令：

- `bash scripts/bootstrap/prepare-images.sh --include-db-source`
- `bash scripts/db/build-source.sh`
- `bash scripts/db/start.sh --mode source --full-observability`

则必须提前准备：

- `ThirdParty/openGauss-server`
- `ThirdParty/openGauss-binarylibs`

要求如下：

- `OPENGAUSS_SOURCE_DIR` 必须指向**包含 `build.sh` 的 openGauss 源码根目录**；
- `OPENGAUSS_BINARYLIBS_DIR` 必须指向**解压后的 binarylibs 根目录**；
- binarylibs 根目录至少应包含：
  - `buildtools/`
  - `kernel/platform/`
  - `kernel/dependency/`

相关配置见：

- `env/compose/.env.example`
- `env/compose/.env`

---

## 3. 第一次推荐这样做：一次性准备完整实验基座

如果你想最快进入“可跑实验、可切换模式、可做观测”的状态，推荐直接执行：

```bash
bash scripts/bootstrap/check-prereqs.sh
bash scripts/bootstrap/init-env.sh
bash scripts/bootstrap/prepare-images.sh --include-db-source
```

这一步会一次性完成：

1. 构建 exporter / TPCC / TPCH 辅助镜像；
2. 构建 `opengauss-dev`；
3. 在开发容器内按 upstream `README.md` 的方式执行 `./build.sh -m <type> -3rd <binarylibs-root>`；
4. 使用 upstream 实际产出的 `mppdb_temp_install/` 作为 install tree 来源；
5. 构建 source runtime image；
6. 将 install tree stage 到 `env/opengauss/build-context/install/`；
7. 打包出 trusted stock baseline image。

执行完成后，你就同时具备了：

- 可直接启动的 `stock` 基座；
- 可继续做源码开发的 `source` 编译链路；
- 完整的 exporter / Prometheus / Grafana 观测栈。

---

## 4. 启动实验环境

### 4.1 推荐先启动 stock mode

第一次上手，建议先用 `stock` 跑基线实验：

```bash
bash scripts/db/start.sh --mode stock --full-observability
```

这条命令会自动完成：

- 启动 openGauss、exporter、Prometheus、Grafana；
- 等待数据库健康检查通过；
- 执行 bootstrap SQL；
- 初始化 benchmark 用户与数据库；
- 安装 observability 视图；
- 应用 baseline 参数。

补充说明：

- 如果本地还没有 `local/opengauss-stock-baseline:latest`，`start.sh --mode stock` 会自动触发源码编译并生成 trusted baseline image；
- 当前 stock mode 已完成回归验证，启动后不会再回退到历史远端 stock 镜像。

### 4.2 需要改源码时，启动 source mode

```bash
bash scripts/db/start.sh --mode source --full-observability
```

说明：

- 启动前会先自动执行 `scripts/db/build-source.sh`；
- source mode 已验证可完成健康检查、bootstrap SQL、observability 视图安装与 `select 1` 连通性检查；
- 当前 source mode 会兼容历史 `${OPENGAUSS_DATA_DIR}` 与 `${OPENGAUSS_DATA_DIR}/data` 两类数据目录布局。

### 4.3 两种模式快速切换

```bash
bash scripts/db/stop.sh --mode stock --full-observability
bash scripts/db/start.sh --mode source --full-observability

bash scripts/db/stop.sh --mode source --full-observability
bash scripts/db/start.sh --mode stock --full-observability
```

注意：

- 推荐把 `stock` 与 `source` 作为“二选一”的运行模式；
- 不建议在同一个 `COMPOSE_PROJECT_NAME` 下同时并行启动两套数据库。

---

## 5. 跑一次完整实验

### 5.1 最推荐的新手起步场景

如果你只想先确认“整条链路通了”，推荐先跑：

```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-steady.yaml
```

这个场景的特点：

- 当前实际 runner 是 **sysbench**；
- 启动快、容易观察；
- 适合作为第一次 baseline 运行。

### 5.2 其他常用场景

#### sysbench + TPCH 注入

```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml
```

适合观察：

- 前台 TP 负载
- 注入查询对 TPS / latency 的影响
- plan-analysis 与 injection 证据链

#### 慢 SQL 压力注入

```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/slow-sql-under-tp.yaml
```

适合观察：

- 慢 SQL 注入
- 会话内存 / spill / temp IO / 执行计划热点

#### TPCH baseline

```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpch-baseline.yaml
```

适合观察：

- 纯 AP / 查询型 workload
- TPCH query 级时长、spill、operator hotspot

补充说明：

- `tpch-baseline.yaml` 当前默认走 seed 复用语义；
- TPCH seed existence-check 已兼容 openGauss，不再依赖 `to_regclass()`；
- 当前已验证 `tpch-baseline` 可在已有 flat files / DB seed 的情况下直接复用数据，不再报 `function to_regclass(unknown) does not exist`。

### 5.3 运行场景时脚本会自动做什么

`scripts/experiment/run-scenario.sh` 会自动完成：

1. 加载基础配置与 scenario YAML；
2. 启动数据库栈（如尚未启动）；
3. 准备 TP 工作负载数据；
4. 按需装载 TPCH 数据；
5. 后台采样数据库内存；
6. 并行运行 TP 负载与注入式查询；
7. 若生成 `.plan`，自动触发离线 plan-analysis；
8. 导出 artifacts；
9. 生成验证与对比结果。

---

## 6. 在 Grafana 中看什么

启动环境后，默认可以访问：

- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`
- Exporter metrics: `http://localhost:9188/metrics`

如果你改过 `env/compose/.env`，则以实际配置为准。

Grafana 默认账号密码：

- 用户名：`admin`
- 密码：`admin`

推荐优先关注 `openGauss Lab` 下这几组 dashboard：

1. `openGauss Memory Overview`
   - 看共享池、会话内存、temp IO、关键参数
2. `Execution Plan Analysis`
   - 看离线 query / operator 证据与数据质量
3. `Pressure Injection Analysis`
   - 看注入查询与前台 TPS / latency 退化
4. `Sysbench Run Analysis`
   - 看真实 sysbench 逐秒 TPS / QPS / latency
5. `TPCH Run Analysis`
   - 看 TPCH query 级 duration / spill / operator hotspot

如果你跑的是 `tpcc-*` 场景，要注意：

- 当前 `TPCC Run Analysis` 仍主要展示 **TPCC 命名场景下的 sysbench 指标**；
- 它不是 BenchBase 原生 TPCC runner 日志视图；
- 但这条 sysbench-derived 时序链路已经完成回归验证：fresh run `20260417-103225-tpcc-steady` 已确认能在 Prometheus 中查询到 TPS / QPS / P95 latency。

---

## 7. 结果会落到哪里

每次运行都会在这里生成独立目录：

```text
experiments/runs/<timestamp>-<scenario>/
```

常见文件包括：

- `validation-summary.tsv`
- `comparison.md`
- `tp/sysbench-run.log`
- `tp/tpch/*.log`
- `tp/tpch/*.plan`
- `plan-analysis/<analysis>/query-summary.tsv`
- `plan-analysis/<analysis>/operator-summary.tsv`
- `observability/db-memory.tsv`

这些 artifacts 会被统一 exporter 自动读取，并进入 Prometheus / Grafana。

---

## 8. 跑完之后怎么验证和对比

### 8.1 校验某次运行是否达标

```bash
bash scripts/experiment/validate-targets.sh --run-dir experiments/runs/<run-id>
```

### 8.2 对比某次运行结果

```bash
bash scripts/experiment/compare-runs.sh --run-dir experiments/runs/<run-id>
```

### 8.3 快速检查 Prometheus / Exporter 是否已经恢复

如果你刚修过环境、重建过 Prometheus，或者想快速确认时序已经进库，可以直接检查：

```bash
curl -s http://localhost:9188/metrics | grep opengauss_run_sysbench_
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=opengauss_run_sysbench_tps{run="<run-id>"}'
```

对于当前已验证通过的 fresh run：

- `20260417-103225-tpcc-steady`

已经确认可以在 Prometheus 中查到：

- `opengauss_run_sysbench_tps`
- `opengauss_run_sysbench_qps`
- `opengauss_run_sysbench_latency_p95_ms`

### 8.4 重新生成离线 plan-analysis

如果你改了 plan 解析逻辑，或想修复旧 run 的 plan-analysis 工件，可以重新执行：

```bash
bash scripts/benchmark/analyze-plan-batch.sh \
  --input-dir experiments/runs/<run-id>/injection/round-1 \
  --output-dir experiments/runs/<run-id>/plan-analysis/round-1
```

---

## 9. 源码开发时的推荐闭环

如果你想修改 openGauss 内核并重新验证，推荐闭环如下：

### 9.1 进入开发容器

```bash
bash scripts/db/dev-shell.sh
```

### 9.2 修改源码并编译

容器内执行：

```bash
dev-build.sh
```

或者在宿主机直接执行：

```bash
bash scripts/db/build-source.sh
```

### 9.3 启动 source mode 复现实验

```bash
bash scripts/db/start.sh --mode source --full-observability
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-steady.yaml
```

### 9.4 如需调试

```bash
bash scripts/db/start-debug.sh
```

---

## 10. TPCH baseline 的数据复用

`tpch-baseline.yaml` 默认已经支持 seed 复用，因此**不需要每次都重新准备 TPCH 数据**。

推荐做法：

1. 第一次运行 `tpch-baseline.yaml`，完成 seed 生成与装载；
2. 后续重复跑同一 scenario，不执行 `scripts/db/reset.sh`；
3. 如只重启数据库，TPCH baseline 会继续复用已有数据；
4. 只有在你需要彻底换数据规模、换 schema 或清理 volume 时，再执行 `reset.sh`。

这对于 AP/HTAP 实验非常重要，可以明显减少重复数据准备时间。

---

## 11. 常用命令速查

### 启动 / 停止 / 重置

```bash
bash scripts/db/start.sh --mode stock --full-observability
bash scripts/db/start.sh --mode source --full-observability

bash scripts/db/stop.sh --mode stock --full-observability
bash scripts/db/stop.sh --mode source --full-observability

bash scripts/db/reset.sh --mode stock
bash scripts/db/reset.sh --mode source
```

### 源码构建 / 调试

```bash
bash scripts/db/build-source.sh
bash scripts/db/build-source.sh --emit-stock-image
bash scripts/db/dev-shell.sh
bash scripts/db/start-debug.sh
```

### 常用 benchmark

```bash
bash scripts/benchmark/run-sysbench.sh --mode prepare --tables 8 --table-size 50000 --threads 64
bash scripts/benchmark/run-sysbench.sh --mode run --tables 8 --table-size 50000 --threads 64 --time 180 --report-interval 1

bash scripts/benchmark/load-tpch.sh --scale-factor 1
bash scripts/benchmark/run-tpch.sh --query-dir benchmarks/tpch/variants/spill-prone
```

---

## 12. 一个最短上手版本

如果你只想最快跑通一遍，请直接执行下面这组命令：

```bash
bash scripts/bootstrap/check-prereqs.sh
bash scripts/bootstrap/init-env.sh
bash scripts/bootstrap/prepare-images.sh --include-db-source
bash scripts/db/start.sh --mode stock --full-observability
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-steady.yaml
```

然后打开：

- Grafana：`http://localhost:3000`
- 查看 `openGauss Lab / Sysbench Run Analysis`
- 查看 `openGauss Lab / TPCC Run Analysis`
- 查看 `experiments/runs/<timestamp>-tpcc-steady/`

如果你想再快速确认一次 Prometheus 里已经有数据，可以补跑：

```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=opengauss_run_sysbench_tps{run="<run-id>"}'
```

这样你就完成了本项目最基础的一次完整实验闭环。
