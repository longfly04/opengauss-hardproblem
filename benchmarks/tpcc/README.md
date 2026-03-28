# TPCC runner

该目录提供基于 [BenchBase](https://github.com/cmu-db/benchbase) 的 TPCC 容器化 runner，用于 openGauss OLTP 基线与稳态吞吐实验。

## 用法
1. 先执行仓库根目录下的 `scripts/bootstrap/prepare-images.sh` 或直接运行 `scripts/benchmark/load-tpcc.sh`。
2. 使用 `scripts/benchmark/load-tpcc.sh` 创建并装载 TPCC 数据。
3. 使用 `scripts/benchmark/run-tpcc.sh` 执行 TPCC 压测。

## 关键设计
- BenchBase 以 Docker 构建，默认在构建过程中拉取官方仓库源码并打包。
- 运行期额外加入 openGauss JDBC 驱动 `org.opengauss:opengauss-jdbc:6.0.3`。
- 配置模板位于 `config/tpcc-config.template.xml`，由脚本按场景参数渲染。
