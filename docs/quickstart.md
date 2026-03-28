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

如需自定义镜像、端口、用户名密码，修改 [env/compose/.env](../env/compose/.env)。

## 构建镜像
```bash
bash scripts/bootstrap/prepare-images.sh
```

会构建：
- 自定义指标 exporter
- TPCC runner（BenchBase）
- TPCH tools（tpch-kit）

## 启动环境
基础环境：
```bash
bash scripts/db/start.sh
```

带 node-exporter/cAdvisor：
```bash
bash scripts/db/start.sh --full-observability
```

## 执行实验
```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/slow-sql-under-tp.yaml
```

## 关闭 / 重置
```bash
bash scripts/db/stop.sh --full-observability
bash scripts/db/reset.sh
```
