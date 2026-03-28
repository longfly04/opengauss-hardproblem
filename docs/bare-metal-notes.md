# Bare-metal notes

虽然本仓库优先支持 Docker，但若需要更接近题目目标的真实性能结果，建议在 Linux 宿主机或裸机 openGauss 上复跑相同场景。

## 建议方式
1. 在宿主机安装 openGauss。
2. 保留 Prometheus / Grafana / runner 容器化。
3. 把连接参数改为宿主机 openGauss 地址。
4. 复用相同的 SQL preset、TPCC/TPCH/sysbench 参数、场景 YAML。

## 原因
容器环境更适合快速验证与相对对比，但如下因素会影响绝对性能：
- cgroup 内存限制
- overlay filesystem
- 宿主机调度抖动
- 容器和主机磁盘路径差异

因此最终结论建议以 Linux 宿主机或裸机复核。
