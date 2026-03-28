# Experiment workflow

## 1. 启动实验底座
```bash
bash scripts/db/start.sh --full-observability
```

## 2. 选择场景
场景位于 [experiments/configs/scenarios/](../experiments/configs/scenarios/)：
- `tpcc-steady.yaml`
- `tpcc-plus-tpch-injection.yaml`
- `slow-sql-under-tp.yaml`

## 3. 运行场景
```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml
```

## 4. 结果目录
每次运行目录结构示例：
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

## 5. 关注指标
- TP 吞吐均值与最小值
- TPS 抖动百分比
- temp bytes / temp files
- session used bytes 峰值
- shared memory used bytes
- active sessions 峰值

## 6. 对比 baseline / tuned
先切换 SQL preset，例如：
- `sql/tuning/baseline_params.sql`
- `sql/tuning/lowmem_params.sql`
- `sql/tuning/pressure_test_params.sql`

然后复跑相同场景，用 `comparison.md` 和 `validation-summary.tsv` 观察差异。
