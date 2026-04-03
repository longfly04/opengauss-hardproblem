# Architecture

## 总体设计
本仓库采用 **基线模式 + 源码开发模式** 的结构：
- `opengauss`：数据库服务名固定不变。
- `og-memory-exporter`：通过 SQL 视图暴露共享内存、会话内存、spill 指标。
- `prometheus` / `grafana`：采集与可视化。
- `sysbench` / `tpcc-runner` / `tpch-tools`：benchmark runner。
- `scripts/experiment/run-scenario.sh`：统一实验编排入口。

## Compose 分层
Compose 被拆成三层：
1. `env/compose/docker-compose.yml`
   - 公共基座。
   - 定义稳定的服务名、网络、卷、benchmark 和 observability 组件。
2. `env/compose/docker-compose.stock.yml`
   - 为 `opengauss` 指定预构建镜像。
3. `env/compose/docker-compose.source.yml`
   - 为 `opengauss` 和 `opengauss-dev` 提供源码编译、调试和运行能力。

`scripts/lib/common.sh` 会根据 `OPENGAUSS_RUNTIME_MODE` 自动拼接对应的 Compose 文件。

## 两种运行模式
### stock mode
- `opengauss` 直接使用 `OPENGAUSS_IMAGE`。
- 适合快速启动、回归验证和做 benchmark baseline。

### source mode
- `opengauss-dev`：源码开发/编译容器，挂载：
  - `OPENGAUSS_SOURCE_DIR`
  - `OPENGAUSS_THIRD_PARTY_DIR`
  - `opengauss_build_cache`
  - `opengauss_install_cache`
- `opengauss`：运行时容器，继续使用服务名 `opengauss`，并挂载：
  - `og_data`
  - `opengauss_build_cache`
  - `opengauss_install_cache`

这样 benchmark、exporter、scenario 脚本不需要改调用方式，只切换 mode 即可。

## 基线模式
以下参数统一由 [env/compose/.env](../env/compose/.env) 管理：
- `DB_SERVICE_NAME`
- `DB_HOST`
- `DB_PORT`
- `DB_CONTAINER_USER`
- `DB_CLIENT_BIN`
- `OPENGAUSS_RUNTIME_MODE`
- `OPENGAUSS_SOURCE_DIR`
- `OPENGAUSS_THIRD_PARTY_DIR`
- `OPENGAUSS_INSTALL_PREFIX`
- `OPENGAUSS_DEBUG_PORT`

`scripts/lib/common.sh` 中的 `compose()`、`wait_for_db()`、`run_gsql()`、`run_gsql_file()` 都基于这些参数工作。

## source mode 生命周期
1. `scripts/db/build-source.sh`
   - 构建 `opengauss-dev` 镜像。
   - 在 `opengauss-dev` 容器内执行 `dev-build.sh`。
   - 编译产物写入 `opengauss_install_cache` 卷。
   - 构建 `opengauss` 运行时镜像。
2. `scripts/db/start.sh --mode source`
   - 启动 `opengauss` 服务。
   - 复用同一套 bootstrap SQL、observability 视图和 tuning preset。
3. `scripts/db/start-debug.sh`
   - 使用同一份编译产物，以 `gdbserver` 模式启动 openGauss。

## 设计原则
1. **Docker 优先**：保证部署和复现实验最简单。
2. **Linux 兼容**：脚本基于 bash，可迁移到 Linux 主机环境。
3. **接口稳定**：实验层尽量不感知 stock/source 差异。
4. **结果留痕**：每次实验都保留完整 artifacts。
5. **开发与实验同链路**：源码修改、编译、调试、压测复用同一环境。
