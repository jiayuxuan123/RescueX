# 破坏性脚本检测规则

## 判定原则

检测器按命令语义和目标路径分级处理：

- 高风险删除目标：`/data` 根、Android 核心数据目录、`/data/adb/modules` 及各 Root 方案模块根、模块目录本身、`/sdcard`、`/storage`。
- 普通生命周期目标：其他 `/data/<directory>` 和 `/data/adb/<directory>`，允许模块清理自身缓存、临时文件和生成目录。
- 模块目录内部的深层路径属于普通生命周期目标，允许隐藏环境模块清理自身工作目录、缓存和临时文件。
- 独立高风险命令：`mkfs.*`、`mke2fs`、`make_f2fs`、`wipefs`、`blkdiscard`、原始块设备 `dd`、明确的 recovery/TWRP/`sm format`/`vdc format` 调用。

## 回归样例

| 脚本命令 | 结果 |
|---|---|
| `rm -rf /data/my-module/cache` | 放行 |
| `find /data/adb/my-module -type f -delete` | 放行 |
| `rm -rf /data/system` | 拦截 |
| `rm -rf /data/adb/modules/other-module` | 拦截 |
| `rm -rf /data/adb/modules/bszip/work/cache` | 放行 |
| `find /data/adb/modules/bszip/work -type f -delete` | 放行 |
| `mkfs.ext4 /dev/block/by-name/userdata` | 拦截 |

规则只产生扫描结果，调用层继续负责禁用模块、隔离脚本和写入告警。
