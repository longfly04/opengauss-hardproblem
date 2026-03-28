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
2. 以 `gdbserver 0.0.0.0:2345` 启动 `gaussdb`。

默认调试端口来自 `OPENGAUSS_DEBUG_PORT`。

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
