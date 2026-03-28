# OLTP runner notes

本目录记录高并发 TP 负载的默认实现：Docker 中的 sysbench pgsql 模式。

## 推荐用法
- 数据准备：`scripts/benchmark/run-sysbench.sh --mode prepare`
- 运行压测：`scripts/benchmark/run-sysbench.sh --mode run`
- 清理数据：`scripts/benchmark/run-sysbench.sh --mode cleanup`

## 默认目的
- 构造高并发 TP 基线。
- 与 TPCH 慢 SQL 注入场景组合，观察 TPS 抖动、内存池变化、spill 与 temp IO。
