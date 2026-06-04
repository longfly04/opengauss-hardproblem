# challenge evidence index

> 范围说明：
> - `repo_*` 列表示本仓库中的文档/脚本/SQL/代码位置。
> - `upstream_source_path` 列表示外部 openGauss 上游源码锚点（`/home/sducs/postgresql-dev/source_code/openGauss-server`）。
> - `status` 取值：`implemented` / `observable-only` / `evidence-only` / `gap`。

| topic | repo_doc_path | repo_code_or_sql_path | upstream_source_path | key_symbols | status |
|---|---|---|---|---|---|
| 难题1-共享内存池观测 | `docs/observability.md` | `sql/observability/memory_pool_views.sql` | `src/common/backend/utils/adt/pgstatfuncs.cpp` | `gs_shared_memory_detail`, `shared_memory_totals` | implemented |
| 难题1-会话内存观测 | `docs/observability.md` | `sql/observability/session_memory_views.sql` | `src/common/backend/utils/adt/pgstatfuncs.cpp` | `gs_session_memory_detail`, `sessionid`, `pg_stat_activity` | implemented |
| 难题1-spill/落盘观测 | `docs/observability.md` | `sql/observability/spill_views.sql`, `tools/exporter/app.py` | `src/gausskernel/optimizer/commands/explain.cpp` | `temp_bytes`, `temp_files`, `Total Written Disk IO` | implemented |
| 难题1-参数可见性（基础） | `docs/openGauss内存池相关文档检索结果.md` | `sql/observability/memory_pool_views.sql` | `src/common/backend/utils/misc/guc/guc_memory.cpp` | `work_mem`, `shared_buffers`, `max_connections` | observable-only |
| 难题1-内存池参数定义 | `docs/openGauss内存池相关文档检索结果.md` | - | `src/common/backend/utils/misc/guc/guc_memory.cpp`, `src/include/knl/knl_guc/knl_instance_attr_memory.h` | `memorypool_enable`, `memorypool_size`, `enable_memory_limit`, `max_process_memory` | evidence-only |
| 难题1-过载逃生机制 | `docs/openGauss内存池相关文档检索结果.md` | - | `src/common/backend/utils/mmgr/mem_snapshot.cpp` | `resilience_memory_reject_percent`, `CleanConnectionByMemory`, `rejectRequest` | evidence-only |
| 难题1-注入压测与抖动验证 | `docs/experiment-workflow.md` | `scripts/experiment/run-scenario.sh`, `scripts/experiment/validate-targets.sh` | - | `tps_jitter_pct`, `peak_temp_bytes`, `peak_active_sessions` | implemented |
| 难题1-动态池/共享池自动化联动控制器 | `难题.md` | - | - | 自动调配策略、在线控制器 | gap |
| 难题2-bound 计算主路径 | `难题.md` | - | `src/gausskernel/cbb/workload/memctl.cpp` | `CalculateQueryMemMain`, `AdjustQueryMem`, `SetNgAssignedQueryMem` | evidence-only |
| 难题2-运行时内存可用量计算 | `难题.md` | - | `src/gausskernel/cbb/workload/dywlm_client.cpp` | `dywlm_client_get_memory_info`, `statement_mem`, `statement_max_mem`, `work_mem` | evidence-only |
| 难题2-query_mem 统计读取接口 | `难题.md` | - | `src/gausskernel/cbb/workload/statctl.cpp` | `WLMGetQueryMem`, `WLMGetQueryMemDN`, `query_mem[0/1]` | evidence-only |
| 难题2-会话级压力观测（现有） | `docs/observability.md` | `sql/observability/session_memory_views.sql`, `scripts/observe/sample-db-memory.sh` | - | `session_used_sum_bytes`, `session_used_max_bytes`, `active_sessions` | observable-only |
| 难题2-算子级内存离线证据 | `benchmarks/tpch/README.md` | `scripts/benchmark/run-tpch.sh`, `scripts/benchmark/profile-tpch.sh` | `src/gausskernel/optimizer/commands/explain.cpp`, `src/gausskernel/runtime/executor/nodeSort.cpp`, `src/include/executor/instrument.h` | `Sort Method`, `Memory Usage`, `Peak Memory Usage`, `sorthashinfo.spaceUsed` | observable-only |
| 难题2-实时逐算子内存时序 | `难题.md` | - | - | operator-level realtime metric stream | gap |
| 难题2-活跃会话优雅回收（非 kill） | `难题.md` | - | `src/common/backend/utils/mmgr/mem_snapshot.cpp` | 当前主要是 `kill_backend` + reject，缺优雅回收策略 | gap |
| Grafana 链路 | `docs/observability.md` | `env/grafana/dashboards/opengauss-memory-overview.json`, `env/grafana/dashboards/pressure-injection-analysis.json` | - | session/shared/temp 指标面板 | implemented |
| Exporter 指标入口 | - | `tools/exporter/app.py` | - | `opengauss_session_used_bytes`, `opengauss_temp_bytes_total`, `opengauss_setting_bytes` | implemented |

## 备注

1. 本索引仅锚定证据位置，不等于“仓库已实现完整自治算法”。
2. 对于 `gap` 项，建议在现有 observability + scenario 框架上逐步引入在线控制器与回收策略原型。