# Source build mode

## 目标
source mode 用于支持以下工作流：
- 挂载 openGauss 源码到容器
- 在容器内编译和调试 openGauss server
- 使用编译产物继续跑现有 benchmark / observability / experiment 流程

## 需要配置的变量
编辑 [env/compose/.env](../env/compose/.env)：
```dotenv
OPENGAUSS_RUNTIME_MODE=source
OPENGAUSS_SOURCE_DIR=./openGauss-server
OPENGAUSS_THIRD_PARTY_DIR=./openGauss-third_party
OPENGAUSS_BUILD_TYPE=debug
OPENGAUSS_INSTALL_PREFIX=/opt/opengauss/install
OPENGAUSS_DEBUG_PORT=2345
```

## 关键容器
### `opengauss-dev`
- 用于编辑源码、安装依赖、执行 `build.sh`。
- 挂载源码目录和 third_party 目录。
- 共享 `opengauss_build_cache` 与 `opengauss_install_cache`。

### `opengauss`
- 作为实验时真正运行的数据库服务。
- 服务名仍然是 `opengauss`。
- 直接复用 `opengauss_install_cache` 中的编译产物。

## 编译流程
```bash
bash scripts/db/build-source.sh
```

该脚本会：
1. 构建 `opengauss-dev` 镜像。
2. 在开发容器内执行 `dev-build.sh`。
3. 将安装产物写入 `opengauss_install_cache`。
4. 构建 `opengauss` 运行时镜像。

## 启动 source mode
```bash
bash scripts/db/start.sh --mode source --full-observability
```

启动后仍然会自动执行：
- bootstrap SQL
- benchmark 用户与数据库初始化
- observability 视图安装
- baseline preset 应用

## 清理
```bash
bash scripts/db/stop.sh --mode source --full-observability
bash scripts/db/reset.sh --mode source
```

`reset.sh` 会移除 Compose 卷，因此也会删除 source mode 的安装产物缓存。
