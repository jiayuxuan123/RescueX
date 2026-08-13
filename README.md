# RescueX - 自动救砖守护

> **维护状态：活跃**。当前版本 **v3.5.10**（versionCode 35020）。
> 安装时可选择是否安装 WebUI；原版 Magisk 可配合 KsuWebUIStandalone 查看 WebUI。
> 代码开源（MIT），欢迎 fork、Issue 与 PR。

Android 自动救砖模块，兼容 Magisk / KernelSU / APatch。

模块启动后监控开机状态：连续重启达到阈值、开机超时未完成时，自动禁用问题模块并恢复系统。

## 功能

- **连续重启救砖**：达到阈值（默认 3 次）自动禁用所有非白名单模块
- **开机超时看门狗**：开机超过指定时长未完成，自动救砖并重启
- **三级渐进式救砖**：嫌疑模块禁用 → 全量禁用 → 人工复核
- **OTA / 补丁更新识别**：区分底层 OTA 和系统补丁，自动调整超时策略
- **嫌疑模块追踪**：启动成功后记录已知良好模块列表，下次失败时对比差异精确定位
- **模块快照管理**：手动拍快照记录当前模块启用状态，出问题可一键回滚
- **跨 Root 救砖事务恢复**：记录 RescueX 实际写入的模块路径与禁用标记；只恢复本事务拥有的标记，避免跨 Magisk / KernelSU / SukiSU / APatch 误启用同名或用户手动禁用的模块
- **自适应启动超时**：基于历史启动耗时移动平均动态调整超时，减少低配设备误报
- **WebUI 与 CLI 管理**：在 KernelSU 管理器 / MMRL 中使用完整 WebUI；Magisk 可通过 `action.sh --cli` 查看诊断、快照、安全模式与救援预览
- **轻量完整性自检**：启动成功后建立 RescueX 核心文件 SHA-256 基线，独立守护进程检查
- **一次性安全模式**：预禁用非白名单模块，下次启动进入安全模式，成功后按事务清单精确恢复
- **诊断包导出**：一键生成脱敏诊断包（zip/tar.gz/txt 自动适配），可选打开 GitHub Issue 草稿
- **安装交互选择 WebUI**：安装/更新时按音量键选择是否安装 WebUI（60 秒无操作自动安装）；原版 Magisk 会提示配合 [KsuWebUIStandalone](https://github.com/5ec1cff/KsuWebUIStandalone) 使用
- **无 WebUI 模式**：选择后自动移除 WebUI 页面（保留配置与原生看门狗），所有参数可直接修改 `/data/adb/rescuex_data/config.conf` 后重启生效
- **可选原生看门狗**：arm64 设备可启用 C 编写的单调时钟看门狗，Shell 回退始终可用

## 安装

在 Magisk / KernelSU / APatch 管理器中刷入 [Releases](https://github.com/jiayuxuan123/RescueX/releases) 页面下载的 zip 包。

安装过程中会显示 **WebUI 安装选择**：

- `[音量+]` 安装 WebUI（推荐）
- `[音量-]` 不安装（无 WebUI 模式，可手动修改 `/data/adb/rescuex_data/config.conf`）
- **60 秒无操作自动安装 WebUI**

> **原版 Magisk 用户**：官方 Magisk 不支持模块 WebUI。如需使用 WebUI，
> 请安装开源应用 [KsuWebUIStandalone](https://github.com/5ec1cff/KsuWebUIStandalone)
> （下载地址见其 Releases 页面），安装后即可在应用内查看本模块 WebUI。

安装完成后重启设备生效。

## 开源仓库

- 仓库地址：https://github.com/jiayuxuan123/RescueX
- 在线更新：模块已内置 `updateJson`，发布新版 Release 后可直接从管理器检查更新

### CLI（Magisk 与自动化诊断）

无原生 WebUI 的环境可在 root shell 中运行：

```sh
sh /data/adb/modules/RescueX/action.sh --cli help
```

全部 CLI 命令均为只读，不会修改模块、配置或救援状态。支持 `status`、`health`、`timeline`、`module-changes`、`snapshots`、`safe-mode status` 和 `simulate`；其中 `simulate` 只预览基于当前状态可能执行的救援策略。

### 兼容性

| Root 方案 | 状态 | 备注 |
|---|---|---|
| Magisk v27+ | 完全兼容 | 安装器使用标准 `update-binary` |
| KernelSU | 兼容 | 安装器兼容 KSU 模块安装 |
| SukiSU Ultra | 兼容 | 同 KernelSU |
| APatch | 实验性 | 安装入口未全面验证，如遇问题请提 Issue |
| MMRL v34242+ | 兼容 | 旧版有 Compose 崩溃，建议升级 |

## 配置参数

| 参数 | 默认值 | 范围 | 说明 |
|---|---|---|---|
| 连续重启阈值 | 3 次 | 1-10 | 达到此次数后触发全量救砖 |
| 开机超时 | 90 秒 | 30-600 | 超时未完成开机则判定失败 |
| OTA 升级超时 | 900 秒 | 60-1800 | 检测到 OTA 时使用此超时 |
| 自适应超时 | 开启 | 开启/关闭 | 基于历史启动耗时动态调整 |
| 用户重启宽限期 | 30 秒 | 5-300 | 短时间内重启不计入失败次数 |
| 补丁更新超时 | 180 秒 | 60-600 | 补丁更新时的超时时间 |
| 轻量完整性自检 | 开启 | 开启/关闭 | 检查核心文件是否缺失或被替换 |
| 看门狗引擎 | Shell | Shell/Native | Native 仅 arm64 且需自检通过 |

## 隐私协议

- RescueX **不联网**、不上传任何数据，所有状态文件仅存储在设备本地
- 诊断包导出是用户主动操作，包含设备型号、系统版本、模块列表、配置和日志
- 诊断包导出前会进行脱敏处理，用户自行决定是否分享
- GitHub Issue 草稿功能仅打开预填页面，不自动上传文件或代管 Token

## 使用须知

- 首次安装默认 `DRY_RUN=true`（仅记录日志不实际禁用模块），验证逻辑无误后再关闭
- 白名单中的模块在救砖时不会被禁用，请将关键模块（字体、音效等）加入白名单
- 一次性安全模式会立即写入禁用标记，下次启动生效，请确认后再布防
- 覆盖更新后如遇异常，可先卸载模块（会彻底清理状态和持久化目录）再重新安装

## 致谢 Credits

RescueX 的兼容适配与 WebUI 能力离不开以下开源项目，在此一并致谢：

| 项目 | 作者 / 组织 | 说明 |
|---|---|---|
| [Magisk](https://github.com/topjohnwu/Magisk) | topjohnwu | 通用 Root 方案与模块框架 |
| [KernelSU](https://github.com/tiann/KernelSU) | tiann | 内核级 Root 方案，模块 WebUI 规范 |
| [SukiSU Ultra](https://github.com/sukisu-ultra/sukisu-ultra) | SukiSU-Ultra | 基于 KernelSU 的分支，支持 KPM |
| [APatch](https://github.com/bmax121/APatch) | bmax121 | 内核级 Root 方案（基于 KernelPatch） |
| [MMRL](https://github.com/DerGoogler/MMRL) | DerGoogler | 支持 WebUI 的模块管理器 |
| [FoxMagiskModuleManager (FoxMMM)](https://github.com/Fox2Code/FoxMagiskModuleManager) | Fox2Code / Androidacy | 开源 Magisk 模块管理器 |
| [KsuWebUIStandalone](https://github.com/5ec1cff/KsuWebUIStandalone) | 5ec1cff | 让原版 Magisk 查看模块 WebUI 的独立应用 |

> **特别感谢 [KsuWebUIStandalone](https://github.com/5ec1cff/KsuWebUIStandalone)**：
> 自 v3.5.10 起，安装器会在原版 Magisk 环境提示该应用，原版 Magisk 用户也能获得完整的 WebUI 体验。

## 许可证

[MIT](LICENSE)
