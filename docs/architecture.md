# Architecture

## 总体设计
本仓库采用 Docker-first 实验架构：

- `opengauss`：数据库实例
- `og-memory-exporter`：通过 SQL 视图抓取内存/会话/spill 指标并暴露为 Prometheus metrics
- `prometheus`：指标采集
- `grafana`：可视化
- `node-exporter` / `cadvisor`：宿主机与容器维度指标（可选）
- `sysbench`、`tpcc-runner`、`tpch-tools`：benchmark runner
- `scripts/experiment/run-scenario.sh`：统一实验编排入口

## 设计原则
1. **Docker 优先**：先保证易部署、易复现。
2. **Linux 兼容**：所有脚本使用 bash，可在 Linux 环境直接运行。
3. **配置驱动**：场景和硬件 profile 使用 YAML 组织。
4. **结果留痕**：每次 run 都有独立 artifacts。
5. **可替换**：后续可将 openGauss 切到宿主机，benchmark / observability 逻辑尽量保持不变。
