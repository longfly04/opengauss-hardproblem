# Challenge mapping

## 难题1：内存池自适应管理
本仓库支持：
- TPCC / sysbench 稳态 TP 流量
- TPCH 慢 SQL 注入
- shared/session memory 观测
- temp IO / spill 观测
- TPS 抖动与 run artifact 输出

用于验证：
- 同等内存下落盘变化趋势
- 慢 SQL 注入时 TP 抖动
- 参数 preset 或后续算法分支带来的收益

## 难题2：动态调整与优雅回收
本仓库支持：
- 高并发 TP 与慢 SQL 共存场景
- 活跃会话、会话内存峰值观测
- 压力窗口内的 temp IO、session memory 变化
- baseline / tuned 对比框架

用于验证：
- TP 基线受扰动程度
- 慢 SQL 高内存占用下 TP 恢复比例
- 参数调整或未来回收机制的效果
