# Source build mode

## 目标

source mode 用于支持以下工作流：
- 挂载 `ThirdParty/openGauss-server` 源码到容器；
- 在 `opengauss-dev` 容器内按 upstream `README.md` 约定调用 `build.sh` 编译 openGauss server；
- 复用同一份编译产物继续跑 benchmark / observability / experiment 流程；
- 将编译好的 install tree 进一步打包为可信 stock baseline image。

当前仓库默认以 **openEuler 24.03 x86_64** 作为 source build 容器基座，并匹配 upstream README 对应的 **gcc10.3 binarylibs**。

## 已验证的启停链路

当前这条源码编译链路已经完成过整链路 smoke test：

- `bash scripts/db/build-source.sh` 可成功构建 `opengauss-dev` 与 source runtime；
- `bash scripts/db/build-source.sh --emit-stock-image` 可成功生成 trusted stock baseline image；
- `bash scripts/db/start.sh --mode source --full-observability` 与 `bash scripts/db/start.sh --mode stock --full-observability` 都已验证可完成健康检查、bootstrap SQL、observability 视图安装与 `select 1` 连通性检查；
- source mode 会自动兼容历史 volume 中的 `${OPENGAUSS_DATA_DIR}` 与 `${OPENGAUSS_DATA_DIR}/data` 两类数据目录布局；
- runtime / stock image 已补齐 source build 运行所需的 third_party 动态库和 locale 支持，可兼容历史 `en_US.utf8` 集群。

## 需要配置的变量

编辑 [env/compose/.env](../env/compose/.env)：

```dotenv
OPENGAUSS_RUNTIME_MODE=source
OPENGAUSS_SOURCE_DIR=./ThirdParty/openGauss-server
OPENGAUSS_BINARYLIBS_DIR=./ThirdParty/openGauss-binarylibs
OPENGAUSS_BUILD_TYPE=debug
OPENGAUSS_DEV_BASE_IMAGE=docker.1ms.run/openeuler/openeuler:24.03-lts
OPENGAUSS_RUNTIME_BASE_IMAGE=docker.1ms.run/openeuler/openeuler:24.03-lts
OPENGAUSS_INSTALL_PREFIX=/opt/opengauss/install
OPENGAUSS_DEBUG_PORT=2345
OPENGAUSS_DEV_DEBUG_PORT=2346
```

其中：
- `OPENGAUSS_SOURCE_DIR` 必须指向 **包含 `build.sh` 的 openGauss 源码根目录**；
- `OPENGAUSS_BINARYLIBS_DIR` 必须指向 **解压后的 binarylibs 根目录**，而不是某个子目录。
- `OPENGAUSS_DEBUG_PORT` 用于 source runtime / `opengauss` 服务里的 `gaussdb` 调试端口；
- `OPENGAUSS_DEV_DEBUG_PORT` 用于 `opengauss-dev` 开发容器的独立调试端口；
- `DB_PORT` 是 benchmark / experiment 统一连接的数据库业务端口；stock 与 source 之间切换时保持不变，避免实验脚本和场景配置因为模式切换而分叉。

## binarylibs 根目录要求

本仓库的自动编译脚本现在按 upstream README 的编译契约检查 binarylibs 根目录，至少应满足：

- `buildtools/`
- `kernel/platform/`
- `kernel/dependency/`

同时脚本还会诊断以下关键路径是否存在：

- `kernel/dependency/llvm/comm/bin/llvm-config`
- `kernel/dependency/cjson/comm/include/cjson/cJSON.h`
- `kernel/dependency/kerberos/comm/include`
- `kernel/dependency/libcgroup/comm/include/libcgroup.h`
- `kernel/dependency/zstd/include/zstd.h`

对于 openEuler 24.03 x86_64，可直接使用 openGauss 文档中的官方 binarylibs 包：

`https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/binarylibs/gcc10.3/openGauss-third_party_binarylibs_openEuler_2403_x86_64.tar.gz`

下载后请解压，并让 `OPENGAUSS_BINARYLIBS_DIR` 指向解压后的 `binarylibs` 根目录。

## 自动编译流程

```bash
bash scripts/bootstrap/check-prereqs.sh
bash scripts/db/build-source.sh
```

`build-source.sh` 会执行以下步骤：

1. 校验 source root 和 binarylibs root；
2. 构建 `opengauss-dev` 镜像；
3. 在开发容器内直接执行 upstream `./build.sh -m <type> -3rd <binarylibs-root>`；
4. 使用 upstream 实际产出的 `mppdb_temp_install/` 作为 install tree 来源；
5. 将 install tree 同步到 `${OPENGAUSS_INSTALL_PREFIX}`；
6. 基于该 install tree 构建 `opengauss` runtime 镜像。

> 注意：虽然 upstream README 某些位置会提到 `dest/`，但当前 upstream `build/script/build_opengauss.sh` 的真实安装输出仍然是 `mppdb_temp_install/`。本仓库的 runtime image 也是基于这一路径进行 staging。

## 生成可信 stock baseline image

```bash
bash scripts/db/build-source.sh --emit-stock-image
```

该命令会在完成 source build 后：

1. 将 `${OPENGAUSS_INSTALL_PREFIX}` 中的 install tree stage 到 `env/opengauss/build-context/install/`；
2. 构建 trusted stock baseline image；
3. 让 stock mode 与 source mode 共用同一条源码编译链路生成的产物。

## 启动 source mode

```bash
bash scripts/db/start.sh --mode source --full-observability
```

启动前 `start.sh` 会先调用 `scripts/db/build-source.sh`，因此 source mode 始终依赖一份可编译的 upstream 源码树和完整的 binarylibs 根目录。

source mode 与 stock mode 共用同一个 `DB_PORT` 约定；如果需要在两种模式之间切换，推荐先停止当前模式，再启动另一模式，而不是在同一个 Compose project 下同时并行启动两套数据库。

启动后仍会自动执行：
- bootstrap SQL
- benchmark 用户与数据库初始化
- observability 视图安装
- baseline preset 应用

## 清理

```bash
bash scripts/db/stop.sh --mode source --full-observability
bash scripts/db/reset.sh --mode source
```

`reset.sh` 会移除 Compose 卷，因此也会删除 source mode 的 build/install cache。