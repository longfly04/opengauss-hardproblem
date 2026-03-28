# Experiment workflow

## 1. 选择运行模式
### stock mode
```bash
bash scripts/db/start.sh --mode stock --full-observability
```

### source mode
```bash
bash scripts/db/build-source.sh
bash scripts/db/start.sh --mode source --full-observability
```

两种模式下，实验入口保持不变：`opengauss` 仍然是数据库服务名，benchmark 默认仍通过 `DB_HOST` / `DB_PORT` 访问数据库。

## 2. 选择场景
场景位于 [experiments/configs/scenarios/](../experiments/configs/scenarios/)：
- `tpcc-steady.yaml`
- `tpcc-plus-tpch-injection.yaml`
- `slow-sql-under-tp.yaml`

## 3. 运行场景
```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml
```

## 4. 场景内部流程
`run-scenario.sh` 会按顺序执行：
1. 启动数据库与 observability 组件。
2. 准备 TP 负载（sysbench 或 TPCC）。
3. 按需加载 TPCH 数据。
4. 启动数据库内存采样。
5. 并发执行 TP 主负载与 TPCH 注入查询。
6. 导出配置、Prometheus 快照、数据库参数与服务日志。
7. 生成 `validation-summary.tsv` 与 `comparison.md`。

## 5. 结果目录
每次运行会生成：
```text
experiments/runs/<timestamp>-<scenario>/
├─ tp/
├─ injection/
├─ observability/
├─ compose/
├─ configs/
├─ prometheus/
├─ validation-summary.tsv
└─ comparison.md
```

## 6. 关注指标
- TP 吞吐均值与最小值
- TPS 抖动百分比
- `temp_bytes` / `temp_files`
- `session_used_bytes` 峰值
- `shared_context_used_bytes`
- active sessions 峰值

## 7. 切换 baseline / tuned / source build
可通过两类开关做对比：
- **SQL preset**：
  - `sql/tuning/baseline_params.sql`
  - `sql/tuning/lowmem_params.sql`
  - `sql/tuning/pressure_test_params.sql`
- **runtime mode**：
  - stock image
  - source build

建议保持同一 scenario YAML，只切换一项变量，便于做对照实验。
