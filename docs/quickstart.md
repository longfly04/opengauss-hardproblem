# Quickstart

## 环境要求
- Linux 或支持 Linux 容器的 Docker 主机
- Docker
- Docker Compose plugin 或 `docker-compose`
- bash

## 初始化
```bash
bash scripts/bootstrap/check-prereqs.sh
bash scripts/bootstrap/init-env.sh
```

如需修改端口、镜像、账号或源码路径，编辑 [env/compose/.env](../env/compose/.env)。

## 运行模式
### 1. stock mode
适合快速启动、回归验证和基线实验。

构建辅助镜像：
```bash
bash scripts/bootstrap/prepare-images.sh
```

启动环境：
```bash
bash scripts/db/start.sh --mode stock --full-observability
```

### 2. source mode
适合修改 openGauss 内核、在容器内编译并继续跑实验。

先在 [env/compose/.env](../env/compose/.env) 中配置：
```dotenv
OPENGAUSS_RUNTIME_MODE=source
OPENGAUSS_SOURCE_DIR=./openGauss-server
OPENGAUSS_THIRD_PARTY_DIR=./openGauss-third_party
OPENGAUSS_BUILD_TYPE=debug
```

构建辅助镜像并编译 openGauss：
```bash
bash scripts/bootstrap/prepare-images.sh --include-db-source
```

或单独编译：
```bash
bash scripts/db/build-source.sh
```

启动 source mode：
```bash
bash scripts/db/start.sh --mode source --full-observability
```

## 开发与调试
进入源码开发容器：
```bash
bash scripts/db/dev-shell.sh
```

启动 gdbserver 调试模式：
```bash
bash scripts/db/start-debug.sh
```

## 执行实验
```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/slow-sql-under-tp.yaml
```

## 关闭 / 重置
关闭环境：
```bash
bash scripts/db/stop.sh --mode stock --full-observability
bash scripts/db/stop.sh --mode source --full-observability
```

重置容器卷与实验输出：
```bash
bash scripts/db/reset.sh --mode stock
bash scripts/db/reset.sh --mode source
```

`reset.sh` 会删除 Compose 卷；在 source mode 下，这也会清空源码编译产物缓存。
