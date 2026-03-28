# Bare-metal notes

本仓库优先支持 Docker，因为它最适合快速部署、源码调试和实验复现。

但如果目标是得到更接近生产或题目最终结论的绝对性能数据，建议在 Linux 宿主机或裸机 openGauss 上复跑相同场景。

## 推荐方式
1. 在 Docker/source mode 中完成源码修改、编译和功能验证。
2. 固化 SQL preset、TPCC/TPCH/sysbench 参数和场景 YAML。
3. 在 Linux 宿主机部署目标版本的 openGauss。
4. 继续复用 Prometheus / Grafana / runner 容器，或直接在宿主机运行脚本。
5. 把 `DB_HOST` / `DB_PORT` 指向宿主机数据库，复跑同一场景。

## 原因
容器环境适合快速验证与相对对比，但绝对性能会受到以下因素影响：
- cgroup 内存限制
- overlay filesystem
- 宿主机调度抖动
- 容器卷与裸机磁盘路径差异

## 建议
- **开发调试阶段**：优先使用 source mode。
- **功能回归阶段**：优先使用 stock mode。
- **最终性能结论**：在 Linux 宿主机或裸机复核。
