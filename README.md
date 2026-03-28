# openGauss memory experiment lab

本仓库已补齐为一个 **Docker 优先、Linux 兼容** 的 openGauss 实验环境，用于围绕 [难题.md](难题.md) 中的两类内存管理课题搭建可部署、可测试、可观测、可复现实验平台。

目标不是直接实现“自适应算法”，而是先提供一套可直接运行的实验底座，便于后续在 baseline / tuned / 算法分支之间复现实验并对比：
- TPCC 稳态吞吐
- TPCH 慢 SQL / 大内存算子注入
- sysbench 高并发 TP 压力
- 内存池 / 会话内存 / spill / temp IO 可观测
- TPS 抖动、落盘变化、TP 恢复能力等指标输出

## 目录结构
- [env/](env/)：Docker Compose、openGauss 配置、Prometheus、Grafana。
- [benchmarks/](benchmarks/)：TPCC、TPCH、sysbench/TP 相关 runner 与查询集。
- [experiments/](experiments/)：基础配置、硬件 profile、场景配置、运行输出。
- [scripts/](scripts/)：启动、压测、观测、编排、结果对比脚本。
- [sql/](sql/)：观测视图和调参 preset。
- [tools/exporter/](tools/exporter/)：自定义 openGauss Prometheus exporter。

## 推荐运行方式
1. Linux 主机或支持 Linux 容器的 Docker 环境。
2. Docker / Docker Compose 可用。
3. 从仓库根目录执行：

```bash
bash scripts/bootstrap/check-prereqs.sh
bash scripts/bootstrap/init-env.sh
bash scripts/bootstrap/prepare-images.sh
bash scripts/db/start.sh --full-observability
```

启动后默认访问：
- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`

## 快速开始
### 1. 启动基础环境
```bash
bash scripts/db/start.sh --full-observability
```

### 2. 运行稳态 TPCC 场景
```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-steady.yaml
```

### 3. 运行 TP + 慢 SQL 注入场景
```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml
```
或：
```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/slow-sql-under-tp.yaml
```

### 4. 查看结果
每次运行会在 [experiments/runs/](experiments/runs/) 下生成独立 run 目录，包含：
- TP 日志
- 注入 SQL 日志
- 采样到的内存时序 TSV
- Prometheus 快照
- 当前 DB 参数导出
- `validation-summary.tsv`
- `comparison.md`

## 支持的实验组件
### TP 负载
- `scripts/benchmark/run-sysbench.sh`：高并发 TP 基线。
- `scripts/benchmark/load-tpcc.sh` / `run-tpcc.sh`：基于 BenchBase 的 TPCC runner。

### 慢 SQL / 大内存算子
- [benchmarks/tpch/variants/pressure-injection/](benchmarks/tpch/variants/pressure-injection/)：运行期注入查询。
- [benchmarks/tpch/variants/spill-prone/](benchmarks/tpch/variants/spill-prone/)：偏落盘/聚合/排序场景。

### 可观测
- [sql/observability/memory_pool_views.sql](sql/observability/memory_pool_views.sql)：共享内存与关键设置观测。
- [sql/observability/session_memory_views.sql](sql/observability/session_memory_views.sql)：会话内存与活动会话观测。
- [sql/observability/spill_views.sql](sql/observability/spill_views.sql)：temp file / temp bytes 观测。
- [env/grafana/dashboards/opengauss-memory-overview.json](env/grafana/dashboards/opengauss-memory-overview.json)：内存总览。
- [env/grafana/dashboards/tpcc-run-analysis.json](env/grafana/dashboards/tpcc-run-analysis.json)：TPCC 过程分析。
- [env/grafana/dashboards/pressure-injection-analysis.json](env/grafana/dashboards/pressure-injection-analysis.json)：压力注入分析。

## 预置场景
- [experiments/configs/scenarios/tpcc-steady.yaml](experiments/configs/scenarios/tpcc-steady.yaml)
- [experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml](experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml)
- [experiments/configs/scenarios/slow-sql-under-tp.yaml](experiments/configs/scenarios/slow-sql-under-tp.yaml)

## 调参 preset
- [sql/tuning/baseline_params.sql](sql/tuning/baseline_params.sql)
- [sql/tuning/lowmem_params.sql](sql/tuning/lowmem_params.sql)
- [sql/tuning/pressure_test_params.sql](sql/tuning/pressure_test_params.sql)

## 注意事项
- 默认以 Docker 为主，适合快速部署、功能验证、相对对比。
- 若要产出最终性能结论，建议保持相同场景配置，再切到 Linux 宿主机 / 裸机 openGauss 复跑。
- 当前仓库重点是“实验环境与验证框架”，不是题目中最终的自适应控制算法实现。

## 参考来源
本仓库在实现中参考了以下公开资料：
- openGauss 容器镜像与安装文档
- openGauss 内存视图与统计视图文档
- BenchBase / BenchmarkSQL / TPCH 工具链公开项目
- sysbench 与 postgres/openGauss JDBC 相关资料

详细说明见：
- [docs/quickstart.md](docs/quickstart.md)
- [docs/experiment-workflow.md](docs/experiment-workflow.md)
- [docs/observability.md](docs/observability.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/bare-metal-notes.md](docs/bare-metal-notes.md)
