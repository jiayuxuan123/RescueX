# RescueX arm64-v8a native watchdog

本目录包含 v3.5.2 随包发布的 `rescuex-watchdog` Android arm64-v8a PIE 二进制。

- 编译器：Android NDK r27c / Clang 18
- 最低 API：26
- 动态加载器：`/system/bin/linker64`
- 依赖：Android bionic `libc.so`、`libdl.so`
- 运行方式：仅在 `WATCHDOG_ENGINE=native` 且设备 ABI 为 `arm64-v8a` 时启用
- 任何架构、权限、自检或启动失败都会回退到 Shell watchdog
