# Dev workflow

## 推荐闭环
### 1. 配置 source mode
编辑 [env/compose/.env](../env/compose/.env)：
```dotenv
OPENGAUSS_RUNTIME_MODE=source
OPENGAUSS_SOURCE_DIR=./ThirdParty/openGauss-server
OPENGAUSS_BINARYLIBS_DIR=./ThirdParty/openGauss-binarylibs
```

### 2. 进入开发容器
```bash
bash scripts/db/dev-shell.sh
```

### 3. 修改源码并编译
```bash
dev-build.sh
```
或在宿主机执行：
```bash
bash scripts/db/build-source.sh
```

### 4. 启动数据库做实验验证
```bash
bash scripts/db/start.sh --mode source --full-observability
```

当前 source mode 已验证可自动完成源码编译、数据库健康检查、bootstrap SQL 与 observability 视图安装；如历史 volume 中仍使用 `${OPENGAUSS_DATA_DIR}/data` 布局，启动脚本也会兼容。

### 5. 跑 benchmark / scenario
```bash
bash scripts/benchmark/run-sysbench.sh --mode run --time 180
bash scripts/benchmark/run-tpcc.sh --duration 300
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml
```

### 6. 如需调试
```bash
bash scripts/db/start-debug.sh
```

## 推荐习惯
- 小改动后先跑 `build-source.sh`，再做 smoke test。
- 需要和官方镜像对比时，保持相同 scenario，仅切换 `--mode stock` / `--mode source`。
- 需要清空安装产物或数据卷时，再执行 `reset.sh`。

## 对比实验建议
1. 先在 stock mode 记录 baseline。
2. 切到 source mode，复跑同一 workload。
3. 对比 `experiments/runs/.../validation-summary.tsv` 和 `comparison.md`。
