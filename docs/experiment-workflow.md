# Experiment Workflow

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

两种模式下实验入口保持不变：数据库服务名仍为 `opengauss`，benchmark 仍通过 `DB_HOST` / `DB_PORT` 访问数据库。

---

## 2. 选择场景

场景位于 `experiments/configs/scenarios/`：
- `tpcc-steady.yaml`
- `tpcc-plus-tpch-injection.yaml`
- `slow-sql-under-tp.yaml`
- `tpch-baseline.yaml`

### 场景语义说明
- `tpcc-steady.yaml`：名字保留为 TPCC steady，但当前实际 runner 是 **sysbench**。
- `tpcc-plus-tpch-injection.yaml`：sysbench 前台 + TPCH 注入查询。
- `slow-sql-under-tp.yaml`：sysbench 前台 + 慢 SQL 压力注入。
- `tpch-baseline.yaml`：纯 TPCH / AP 基线运行。

因此 Grafana 中：
- `Sysbench Run Analysis` 和 `TPCC Run Analysis` 当前都建立在 `tp/sysbench-run.log` 上；
- `TPCH Run Analysis` 建立在 `tp/tpch/*.plan`、`plan-analysis/tpch/*` 和可选 `summary.tsv` 上。

---

## 3. 运行场景

```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml
```

---

## 4. 场景内部流程

`run-scenario.sh` 典型流程：
1. 启动数据库和 observability 组件；
2. 准备 TP 负载（sysbench 或 TPCC）；
3. 按需加载 TPCH 数据；
4. 启动数据库内存采样；
5. 并发执行前台 TP 与注入查询；
6. 导出 Prometheus 快照、配置、参数和服务日志；
7. 生成 `validation-summary.tsv`、`comparison.md` 和 plan-analysis 工件。

---

## 5. 结果目录与 Grafana 数据源

每次运行生成：

```text
experiments/runs/<timestamp>-<scenario>/
├─ tp/
│  ├─ sysbench-run.log
│  └─ tpch/
│     ├─ *.log
│     ├─ *.plan
│     └─ summary.tsv          # 旧 run 可能缺失
├─ injection/
│  └─ round-*/
├─ observability/
├─ compose/
├─ configs/
├─ plan-analysis/
│  └─ <analysis>/
│     ├─ grafana-summary.json
│     ├─ query-summary.tsv
│     └─ operator-summary.tsv
├─ prometheus/
├─ validation-summary.tsv
├─ run-summary.env
└─ comparison.md
```

`tools/exporter/app.py` 会统一读取这些工件并导出：
- `validation-summary.tsv` → `opengauss_run_validation_metric`
- `tp/sysbench-run.log` → `opengauss_run_sysbench_*`
- `tp/tpch/*.plan` / `summary.tsv` / `plan-analysis/tpch/*` → `opengauss_run_tpch_query_*`、`opengauss_plan_*`
- `injection/round-*` + `plan-analysis/round-*` → `opengauss_injection_*`

---

## 6. TPCH baseline 复用策略

`tpch-baseline.yaml` 默认用于“加载一次、重复复用”的 AP 基线：
- `tp_runner: tpch`
- `tpch_scale_factor: 1`
- `tpch_data_policy: reuse_if_present`
- `tpch_seed_name: sf1-local`
- `dataset_profile_file: benchmarks/datasets/profiles/small-local.yaml`

语义：
1. 第一次运行生成 seed flat files 并装载数据库；
2. 后续只要 volume 还在、manifest 匹配，就复用已有 TPCH 数据；
3. 如果数据库被重启但 volume 没删，scenario 会跳过重复生成和重复装载；
4. 如果表丢失但 seed 文件仍在，会复用 seed 重新装载。

---

## 7. 历史 run 的兼容与修复

### 1. 旧 TPCH run 缺少 `summary.tsv`
当前 exporter 已兼容回退到：
- `plan-analysis/tpch/query-summary.tsv`
- `tp/tpch/*.plan`
- `tp/tpch/*.log`

所以旧 run 也能出现在 `TPCH Run Analysis` 中。

### 2. 旧 plan-analysis 仍有异常时长
部分早期 run 的 `query-summary.tsv` / `operator-summary.tsv` 可能保留修复前的异常值。当前行为：
- exporter 会将异常 query 标记为 `duration_sanity_ok=0`；
- 主 dashboard 会在 TopN 图里过滤这些 flagged query；
- 质量面板会显示 invalid rows / flagged queries。

如果你希望旧 run 被彻底纠正，请重新执行对应 run 的离线 plan-analysis。

---

## 8. 关注指标

### 前台稳定性
- `avg_tps`
- `min_tps`
- `tps_jitter_pct`
- `errors_per_sec`
- `reconnections_per_sec`

### 内存 / spill
- `opengauss_shared_context_used_bytes`
- `opengauss_session_used_bytes`
- `opengauss_session_memory_used_ratio`
- `opengauss_temp_bytes_total`
- `opengauss_temp_files_total`

### 算子级离线证据
- `opengauss_plan_query_execution_time_ms`
- `opengauss_plan_query_temp_written_blocks`
- `opengauss_plan_query_external_sort_nodes`
- `opengauss_plan_operator_sort_space_used_kb_max`
- `opengauss_plan_operator_exclusive_duration_ms_sum`

---

## 9. 切换 baseline / tuned / source build

建议保持同一 scenario YAML，只切换一个变量做对照：

- **SQL preset**
  - `sql/tuning/baseline_params.sql`
  - `sql/tuning/lowmem_params.sql`
  - `sql/tuning/pressure_test_params.sql`

- **runtime mode**
  - stock image
  - source build
