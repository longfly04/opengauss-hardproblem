# TPCH tools and query packs

该目录提供两类能力：
- 使用 `tpch-kit` 生成 TPCH 数据与官方查询模板。
- 提供更适合内存压力实验的 spill-prone / pressure-injection 查询集合。

## 目录说明
- `schema.sql`：TPCH 基础表结构。
- `queries/`：可放置官方 qgen 生成结果。
- `variants/spill-prone/`：偏落盘、排序/聚合压力场景。
- `variants/pressure-injection/`：用于 TP 业务运行中途注入的慢 SQL。
- `generated/`：运行 `load-tpch.sh` 后自动生成的数据与查询。

## 用法
- 生成并加载数据：`scripts/benchmark/load-tpch.sh`
- 执行单条或一组查询：`scripts/benchmark/run-tpch.sh`
- 在 TP 基线期间注入压力 SQL：`scripts/benchmark/inject-slow-sql.sh`
