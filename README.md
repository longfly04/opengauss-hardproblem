# openGauss memory experiment lab

本仓库提供一套 **Docker 优先、Linux 兼容** 的 openGauss 实验环境，用于围绕 [难题.md](难题.md) 中的内存管理课题做部署、压测、观测、对比和源码调试。

当前同时支持两种运行模式：
- **stock mode**：直接使用预构建 openGauss 镜像，适合快速回归和基线实验。
- **source mode**：在容器内挂载 openGauss 源码与 third_party，完成编译、调试，并继续跑同一套 benchmark / observability / experiment 脚本。

## 目录结构
- [env/](env/)：Compose、openGauss 容器、Prometheus、Grafana。
- [benchmarks/](benchmarks/)：TPCC、TPCH、sysbench runner 与查询集。
- [experiments/](experiments/)：场景配置、硬件 profile、运行输出。
- [scripts/](scripts/)：启动、压测、观测、实验编排脚本。
- [sql/](sql/)：观测视图与调参 preset。
- [tools/exporter/](tools/exporter/)：自定义 Prometheus exporter。

## 快速开始
### stock mode
```bash
bash scripts/bootstrap/check-prereqs.sh
bash scripts/bootstrap/init-env.sh
bash scripts/bootstrap/prepare-images.sh
bash scripts/db/start.sh --mode stock --full-observability
```

### source mode
先在 [env/compose/.env](env/compose/.env) 中配置：
- `OPENGAUSS_RUNTIME_MODE=source`
- `OPENGAUSS_SOURCE_DIR`
- `OPENGAUSS_THIRD_PARTY_DIR`

然后执行：
```bash
bash scripts/bootstrap/check-prereqs.sh
bash scripts/bootstrap/init-env.sh
bash scripts/bootstrap/prepare-images.sh --include-db-source
bash scripts/db/start.sh --mode source --full-observability
```

启动后默认访问：
- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`

## 常用命令
### 启动实验环境
```bash
bash scripts/db/start.sh --mode stock --full-observability
bash scripts/db/start.sh --mode source --full-observability
```

### 进入源码开发容器
```bash
bash scripts/db/dev-shell.sh
```

### 单独编译源码
```bash
bash scripts/db/build-source.sh
```

### 启动 gdbserver 调试模式
```bash
bash scripts/db/start-debug.sh
```

### 运行实验场景
```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-steady.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/slow-sql-under-tp.yaml
```

## 支持的实验组件
### TP 负载
- `scripts/benchmark/run-sysbench.sh`
- `scripts/benchmark/load-tpcc.sh`
- `scripts/benchmark/run-tpcc.sh`
- `scripts/benchmark/load-tpch.sh`
- `scripts/benchmark/run-tpch.sh`

### 可观测能力
- [sql/observability/memory_pool_views.sql](sql/observability/memory_pool_views.sql)：共享内存与关键配置观测。
- [sql/observability/session_memory_views.sql](sql/observability/session_memory_views.sql)：会话内存与活动会话观测。
- [sql/observability/spill_views.sql](sql/observability/spill_views.sql)：temp file / temp bytes 观测。
- [env/grafana/dashboards/opengauss-memory-overview.json](env/grafana/dashboards/opengauss-memory-overview.json)：内存总览。
- [env/grafana/dashboards/tpcc-run-analysis.json](env/grafana/dashboards/tpcc-run-analysis.json)：TPCC 分析。
- [env/grafana/dashboards/pressure-injection-analysis.json](env/grafana/dashboards/pressure-injection-analysis.json)：注入场景分析。

## 实验输出
每次运行会在 [experiments/runs/](experiments/runs/) 下生成独立目录，包含：
- TP 日志
- 注入 SQL 日志
- 内存时序 TSV
- Prometheus 快照
- 当前参数导出
- `validation-summary.tsv`
- `comparison.md`

## 更多说明
- [docs/quickstart.md](docs/quickstart.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/experiment-workflow.md](docs/experiment-workflow.md)
- [docs/source-build.md](docs/source-build.md)
- [docs/debugging.md](docs/debugging.md)
- [docs/dev-workflow.md](docs/dev-workflow.md)
- [docs/observability.md](docs/observability.md)
- [docs/bare-metal-notes.md](docs/bare-metal-notes.md)
