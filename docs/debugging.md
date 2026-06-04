# Debugging

## 进入开发容器
```bash
bash scripts/db/dev-shell.sh
```

进入后可直接：
- 编辑 `/workspace/openGauss-server`
- 运行 `dev-build.sh`
- 手工执行 `gdb`、`gdbserver`、`gs_ctl`

## 使用 gdbserver 启动 openGauss
```bash
bash scripts/db/start-debug.sh
```

该命令会：
1. 确保 source mode 编译产物已生成。
2. 以 `gdbserver 0.0.0.0:2345` 启动 source runtime 容器中的 `gaussdb`。
3. 保持 benchmark / experiment 继续沿用统一的 `DB_PORT`，只拆分调试入口端口。

调试端口约定：
- `OPENGAUSS_DEBUG_PORT`：source runtime / `opengauss` 服务的 `gaussdb` 调试端口。
- `OPENGAUSS_DEV_DEBUG_PORT`：`opengauss-dev` 开发容器内手工运行 `dev-debug.sh` 时对宿主机暴露的调试端口。

这样 benchmark / experiment 仍统一连接同一个 `DB_PORT`，不会因为 stock/source 切换而改变实验脚本；只有调试入口端口在 source mode 下区分 runtime 与 dev 容器。

## 本地 attach 示例
```bash
gdb /path/to/gaussdb
target remote localhost:2345
```

## 手工调试常用命令
在 `opengauss-dev` 容器内：
```bash
dev-build.sh
dev-run.sh
dev-debug.sh
```

## 调试建议
- 需要完整 benchmark / observability 链路时，使用 `scripts/db/start.sh --mode source --full-observability`。
- 需要单步调试 postmaster 或 backend 启动路径时，使用 `scripts/db/start-debug.sh`。
- 调试前尽量先执行一次 `build-source.sh`，确保 `opengauss_install_cache` 中的产物是最新的。
- 如果历史 volume 中的数据目录在 `${OPENGAUSS_DATA_DIR}/data`，当前 source runtime 已兼容该布局；通常不需要为了切换到新版脚本而手工搬迁数据目录。
- 如果历史集群配置仍写着 `en_US.utf8`，当前 runtime / stock image 已补齐 locale 支持，并在必要时做兼容性归一化；遇到旧集群时优先复用现有 volume，而不是重新 initdb。
