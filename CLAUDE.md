# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This repo is an openGauss memory experiment lab. It supports two interchangeable runtime modes:
- `stock`: run against a **trusted baseline image built from this repo's source build flow** for stable baseline and regression experiments.
- `source`: mount openGauss source and third_party into containers, compile inside `opengauss-dev`, then run the compiled server through the same benchmark/observability pipeline.

The main workflow is: start the lab, run a benchmark or scenario, collect artifacts under `experiments/runs/`, and compare baseline vs tuned/source runs.

## Common commands

### Initial setup
```bash
bash scripts/bootstrap/check-prereqs.sh
bash scripts/bootstrap/init-env.sh
```

`init-env.sh` creates `env/compose/.env` from `.env.example` if missing and prepares local output directories.

### Build helper images
```bash
bash scripts/bootstrap/prepare-images.sh
bash scripts/bootstrap/prepare-images.sh --include-db-source
```

### Start / stop the lab
```bash
bash scripts/db/start.sh --mode stock --full-observability
bash scripts/db/start.sh --mode source --full-observability

bash scripts/db/stop.sh --mode stock --full-observability
bash scripts/db/stop.sh --mode source --full-observability
```

Useful flags for `start.sh`:
- `--skip-init`: skip bootstrap SQL.
- `--apply-sql <repo-relative-sql-path>`: apply an extra preset after bootstrap, e.g. `sql/tuning/pressure_test_params.sql`.

### Reset state
```bash
bash scripts/db/reset.sh --mode stock
bash scripts/db/reset.sh --mode source
```

`reset.sh` removes Compose volumes. In `source` mode this also deletes compiled install cache.

### Source-mode development
```bash
bash scripts/db/build-source.sh
bash scripts/db/dev-shell.sh
bash scripts/db/start-debug.sh
```

Inside `opengauss-dev`, common commands are:
```bash
dev-build.sh
dev-run.sh
dev-debug.sh
```

### Benchmarks
```bash
bash scripts/benchmark/run-sysbench.sh --mode prepare --tables 8 --table-size 50000 --threads 64
bash scripts/benchmark/run-sysbench.sh --mode run --tables 8 --table-size 50000 --threads 64 --time 180 --report-interval 1
bash scripts/benchmark/run-sysbench.sh --mode cleanup --tables 8 --table-size 50000 --threads 64

bash scripts/benchmark/load-tpcc.sh --scalefactor 10 --terminals 32 --duration 300
bash scripts/benchmark/run-tpcc.sh --scalefactor 10 --terminals 32 --duration 300

bash scripts/benchmark/load-tpch.sh --scale-factor 1
bash scripts/benchmark/run-tpch.sh --query-file benchmarks/tpch/variants/spill-prone/<query>.sql
bash scripts/benchmark/run-tpch.sh --query-dir benchmarks/tpch/variants/spill-prone
```

### Scenario orchestration
```bash
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-steady.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpcc-plus-tpch-injection.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/slow-sql-under-tp.yaml
bash scripts/experiment/run-scenario.sh experiments/configs/scenarios/tpch-baseline.yaml
```

### Result comparison and validation
```bash
bash scripts/experiment/validate-targets.sh --run-dir experiments/runs/<run-id>
bash scripts/experiment/compare-runs.sh --run-dir experiments/runs/<run-id>
```

## Architecture overview

### Compose layering and runtime switching
Compose is intentionally split so callers do not need different command shapes per runtime mode:
- `env/compose/docker-compose.yml`: common stack: `opengauss`, exporter, Prometheus, Grafana, sysbench, TPCC, TPCH.
- `env/compose/docker-compose.stock.yml`: pins `opengauss` to the trusted stock baseline image.
- `env/compose/docker-compose.source.yml`: replaces `opengauss` with a source-built runtime and adds `opengauss-dev`.
- `env/compose/docker-compose.observability.yml`: host-level observability services (`node-exporter`, `cadvisor`) used by `--full-observability`.

`scripts/lib/common.sh` is the key integration layer. Its `compose()` / `compose_obs()` helpers choose the correct Compose file set from `OPENGAUSS_RUNTIME_MODE`, and its `run_gsql*` helpers are the base API used by most scripts.

### Core services
- `opengauss`: stable service name used by all scripts and runners in both modes.
- `opengauss-dev`: only in `source` mode; interactive build/debug container mounting source and third_party trees.
- `og-memory-exporter`: unified Python Prometheus exporter (`tools/exporter/app.py`) that reads both `lab_obs.*` SQL views and run artifacts under `experiments/runs/`.
- `prometheus` / `grafana`: scrape and dashboard layer.
- `sysbench`, `tpcc-runner`, `tpch-tools`: workload containers invoked through scripts rather than manually.

### Observability pipeline
`start.sh` installs observability SQL via `sql/observability/install_views.sql`, which wires these view sets:
- shared memory: `memory_pool_views.sql`
- session memory: `session_memory_views.sql`
- spill/temp IO: `spill_views.sql`
- execution plan metrics: `execution_plan_views.sql`

`tools/exporter/app.py` is the single exporter for project metrics. It now emits:
- real-time DB metrics from `lab_obs.*`
- validation summary metrics from `validation-summary.tsv`
- per-second sysbench metrics from `tp/sysbench-run.log`
- TPCH query-level metrics from `tp/tpch/` and `plan-analysis/tpch/`
- offline plan-analysis quality metrics such as `opengauss_plan_query_duration_sanity_ok`
- injection round/query metrics from `injection/round-*` and `plan-analysis/round-*`

Prometheus should only scrape `og-memory-exporter:9188` for project-specific metrics.

Dashboard responsibilities are currently:
- `openGauss Memory Overview`: shared/session/temp/settings overview.
- `Execution Plan Analysis`: offline query/operator evidence plus data-quality panels.
- `Pressure Injection Analysis`: injected query evidence plus foreground TPS/latency degradation.
- `Sysbench Run Analysis`: true sysbench time-series from runner logs.
- `TPCC Run Analysis`: current TPCC-named scenarios are still sysbench-driven, so this dashboard currently renders sysbench-derived metrics for those scenarios.
- `TPCH Run Analysis`: TPCH query-level duration/spill/operator evidence.

Offline capture/export helpers remain:
- `scripts/observe/sample-db-memory.sh`
- `scripts/observe/snapshot-metrics.sh`
- `scripts/observe/export-run-artifacts.sh`

### Experiment orchestration
`scripts/experiment/run-scenario.sh` is the main end-to-end entrypoint. It:
1. Loads base config plus scenario YAML from `experiments/configs/`.
2. Starts the DB stack if `DOCKER_MODE=compose`.
3. Prepares TP workload data (sysbench or TPCC).
4. Optionally loads TPCH data.
5. Starts background DB memory sampling.
6. Runs the main TP workload and optional injected slow SQL in parallel.
7. Exports artifacts, validates results, writes `comparison.md`, and triggers offline plan-analysis when `.plan` files are present.

Scenario outputs are written to `experiments/runs/<timestamp>-<scenario>/` with logs, snapshots, copied configs, `validation-summary.tsv`, and `comparison.md`.

### Configuration model
- Runtime defaults live in `env/compose/.env.example`; local edits go in `env/compose/.env`.
- Scenario composition uses flat YAML fragments from:
  - `experiments/configs/base/`
  - `experiments/configs/hardware-profiles/`
  - `experiments/configs/scenarios/`
- `scripts/lib/common.sh:load_flat_yaml()` converts those flat YAML files into environment variables consumed by orchestration scripts.

### Benchmark roles
- `scripts/benchmark/run-sysbench.sh`: OLTP baseline/high-concurrency driver. Current `tpcc-steady` and `tpcc-plus-tpch-injection` scenarios are sysbench-driven.
- `scripts/benchmark/load-tpcc.sh` + `run-tpcc.sh`: BenchBase-backed TPCC flow. Do not assume historical runs already contain `tp/tpcc-run.log` artifacts.
- `scripts/benchmark/load-tpch.sh` + `run-tpch.sh`: analytical/query-stress flow.
- `scripts/benchmark/inject-slow-sql.sh`: pressure injection during TP runs.
- `scripts/benchmark/analyze-plan-batch.sh` + `analyze-plan-batch.py`: offline plan-analysis pipeline backed by the vendored PEV2 parser.

## Project-specific notes

- `scripts/db/start.sh --mode source` always triggers `scripts/db/build-source.sh` first; do not assume source artifacts are already current.
- Benchmark containers connect to `opengauss` on container port `5432`, not the host-mapped port.
- If you need to compare stock vs source behavior, keep the same scenario YAML and change only runtime mode or SQL preset so result diffs stay meaningful.
- `tools/exporter/` is a small Python service owned by this repo; `ThirdParty/pev2/` is a vendored upstream frontend project with its own Node/Vite workflow (`npm test`, `npm run build`, `npm run lint`) and should be treated separately from the main lab scripts.
- Historical TPCH runs may lack `tp/tpch/summary.tsv`; the exporter now falls back to `plan-analysis/tpch/query-summary.tsv` plus `tp/tpch/*.plan` and `tp/tpch/*.log`.
- Historical plan-analysis outputs from before the duration fix may contain absurd query/operator runtimes. The exporter flags them via `opengauss_plan_query_duration_sanity_ok`, `opengauss_plan_query_invalid_operator_count`, and `opengauss_plan_analysis_invalid_rows_total`, and dashboards filter them from primary Top-N views.
- If you need corrected artifacts on disk for an older run, re-run `scripts/benchmark/analyze-plan-batch.sh` against that run's `.plan` directory instead of relying only on exporter-side sanitization.
- Keep dashboard titles and documentation aligned with actual runner semantics. Today some `tpcc-*` scenarios are still sysbench-driven rather than BenchBase TPCC-driven.
- `docs/latest-capabilities.md` is the best repo-local snapshot of the current exporter/dashboard architecture, scenario semantics, compatibility behavior, and known limitations.
