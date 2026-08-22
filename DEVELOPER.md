# RescueX 开发者接手文档

> 本文档面向后续维护者与 AI Agent，说明 RescueX 的架构、关键决策、发布流程与测试方法。
> 项目采用 MIT 开源协议，欢迎 fork 与改进。

## 1. 项目概览

RescueX 是一个 Magisk / KernelSU / APatch 模块，用于**自动救砖**：
监控启动失败次数与开机超时，在确认持续无法进入系统时，按三级策略逐步
（嫌疑模块禁用 → 验证式全量禁用 → 日志审计）恢复设备。

- 仓库：`jiayuxuan123/RescueX`（GitHub）
- 当前版本：v3.5.10-r3（versionCode 350203）
- 兼容：Android 9+ (API 28+)，Magisk 20.4+ / KernelSU / APatch / SukiSU / MMRL

## 2. 目录结构与职责

| 路径 | 职责 |
| --- | --- |
| `module.prop` | 模块元数据（id/version/versionCode/updateJson） |
| `customize.sh` | 安装/更新脚本：API 检查、管理器检测、**WebUI 安装选择（音量键）**、配置迁移、权限设置 |
| `common.sh` | 核心库：路径/状态/配置/历史/统计/完整性/救砖状态机（被所有脚本 source） |
| `ota-detection.sh` | 跨厂商 OTA 检测层：上次成功启动构建基线、兼容信号兜底、一次性手动保护与诊断状态 |
| `post-fs-data.sh` | 开机早期阶段：启动模式检测、失败判定、看门狗启动、状态写入 |
| `service.sh` | 系统服务阶段：等待启动完成、提交 SUCCESS、完整性守护启动 |
| `watchdog.sh` | 看门狗：按配置轮询启动进度，超时执行救砖 |
| `integrity.sh` | 完整性守护进程：周期性哈希核心文件，检测被篡改 |
| `v351-safety.sh` | v3.5.1 安全层（**最后加载**）：fail-closed 状态机、救砖事务 journal、动态完整性清单 |
| `features-v35.sh` | v3.5 功能层：一次性安全模式、模块变更扫描、健康时间线 |
| `action.sh` | CLI 入口：`action.sh --cli rescue status/restore`、`ota status/arm/clear` 等 |
| `uninstall.sh` | 卸载清理 |
| `native/rescuex_watchdog.c` | 可选原生看门狗（默认 Shell 引擎，原生需显式 `WATCHDOG_ENGINE=native`） |
| `webroot/` | WebUI 页面（index.html/script.js/style.css/workspace-v2.css + `state/` 状态目录 + `arm64-v8a/` 原生二进制） |
| `META-INF/com/google/android/update-binary` | 标准 Magisk 安装引导 |

## 3. 关键数据位置

| 路径 | 内容 |
| --- | --- |
| `$MODDIR/webroot/state/` | 模块内状态目录：`config.conf`、`whitelist.conf`、`boot_status`、`boot_history`、`boot_duration_history`、`ota_detection_status`、`rescue.log`、快照、完整性基线等 |
| `/data/adb/rescuex_data/` | **外部持久化镜像**（模块更新/卸载不丢失）：config、历史、统计、完整性基线，以及 `ota_build_baseline` / `ota_update_pending` |
| `/data/adb/rescuex_data/config.conf` | **无 WebUI 模式下用户手动修改的配置文件**（模块内 state 有同内容副本，运行时以 state 为准，启动时从持久化恢复缺失项） |

### config.conf 常用项

```
REBOOT_THRESHOLD=3        # 连续重启阈值
BOOT_TIMEOUT_SEC=90       # 开机超时（秒）
OTA_TIMEOUT_SEC=900       # OTA 更新后的超时
ENABLED=true              # 模块总开关
DRY_RUN=true              # 演练模式（默认 true，不会真实改动模块；验证后改为 false）
PROGRESSIVE_RESCUE=true   # 渐进式三级救砖
USER_REBOOT_GRACE_SEC=30  # 用户主动重启宽限期
WATCHDOG_ENGINE=shell     # shell | native
INTEGRITY_CHECK_ENABLED=true
```

## 4. 重要架构决策（历史修复沉淀，勿轻易回退）

1. **RescueX 不拥有 Root 管理器更新队列**：`/data/adb/modules_update`、
   `/data/adb/modules_update_mmrl` 属于 Magisk/KernelSU/APatch 及其前端，
   不得移动、回放、删除或在其后触发 RescueX 重启（v3.5.9-r1 起）。
2. **BOOT_TOKEN 仅作诊断**：token 变化不能单独作为失败证据计入救砖判定；
   需要显式 `FAILURE/TEST_FAILURE` 状态，或超宽限期的未完成启动（v3.5.9-r1 起）。
3. **DRY_RUN 默认开启**：首次安装处于演练模式，用户验证后显式关闭
   （customize.sh 写入默认配置；WebUI/配置文件均可改）。
4. **事务 journal 恢复**：救砖禁用恢复必须基于 RescueX 自己写入且路径可验证
   的 journal；同名模块跨 Root 根目录禁止猜测性恢复（v3.5.8）。
5. **完整性基线动态化**：v351-safety.sh 的 `integrity_target_files()`
   只把**实际存在**的 webroot 页面文件纳入哈希——无 WebUI 模式下
   移除页面不会被误报为被篡改（v3.5.10）。
6. **service 终态保护**：`RESCUED`/`FAILURE` 终态不会被迟到的 service 覆盖。
7. **状态目录在 webroot/state**：无 WebUI 模式**必须保留** `webroot/state` 与
   `webroot/arm64-v8a`，只删除页面文件与 assets。
8. **启动统计配对计数**（v3.5.10-r1）：`compute_boot_stats` 的 SUCCESS
   只统计「boot token 能配对到 START 行」的 SERVICE 行，孤儿行不计、
   重复行只计一次；救砖/失败会正确反映在成功率上。禁止回退为
   "数所有 SERVICE 行" 的口径（会导致成功率虚高/永远 100%）。
9. **OTA 基线只在启动成功后推进**（v3.5.10-r3）：`ota-detection.sh`
   以当前系统与上一次确认 `SUCCESS` 的构建身份差异作为主判断，旧的
   OTA/Recovery/BCB/update_engine 信号只作兼容兜底。`service.sh` 必须先
   提交 `SUCCESS`，再调用 `ota_commit_build_baseline`；失败的新系统绝不能覆盖
   旧基线。此层只决定超时和诊断，禁止接入失败计数、模块禁用、事务恢复、
   看门狗触发或重启策略。

## 5. 安装交互（v3.5.10）

`customize.sh` 在安装/更新时：

1. 检测管理器：KernelSU / SukiSU / APatch / Magisk / 未知。
2. 显示 WebUI 选择：
   - `[音量+]` 安装 WebUI（推荐）
   - `[音量-]` 无 WebUI 模式（移除页面，保留配置，手动改 `config.conf`）
   - **60 秒无按键自动安装 WebUI**（`wait_webui_volkey()`，无 getevent 环境直接默认）
3. 原版 Magisk（无 KSU/APATCH 环境、未检测到 MMRL）：提示"不支持 WebUI"，
   并给出 [KsuWebUIStandalone](https://github.com/5ec1cff/KsuWebUIStandalone) 下载地址。
4. 无 WebUI 模式删除：`webroot/index.html`、`script.js`、`style.css`、
   `workspace-v2.css`、`assets/`；保留 `state/`、`arm64-v8a/`。

## 6. 发布流程（新版本）

1. 在 `audit/rescuex-3.5.10`（工作副本）改代码；**原始 ZIP 归档不动**。
2. 版本统一 bump：`module.prop`、`common.sh`（RX_VERSION/RX_VERSION_CODE）、
   `customize.sh`（RX_VERSION）、`webroot/script.js`（APP_VERSION/APP_VERSION_CODE）、
   `webroot/index.html`、原生看门狗说明/源码版本行、RELEASE-NOTES、CHANGELOG。
   新增或修改 OTA 流程时，还必须同步 `ota-detection.sh`、`post-fs-data.sh`、
   `service.sh`、`v351-safety.sh` 与相关测试。
   **版本号规则**（v3.5.10-r1 起）：主版本 `v3.5.10` = `35020`；
   同级修复用 `-rN` 后缀，versionCode 在 `35020` 后追加两位递增
   （`350201`、`350202`…）。**不要**为小修复跳主版本号
   （否则 versionCode 会快速涨级，也容易撞号）。
3. 校验：`sh -n` 全部脚本 + `node --check webroot/script.js`。
4. 打包：生成 ZIP 后运行 `python3 tests/package_layout_test.py RescueX-vX.zip`。
   安装包必须排除 `.git/`、临时文件、历史 ZIP、`tests/` 和 `webroot/state/`；
   后者包含设备日志、模块库存与救砖事务，绝不能随发布包分发。
5. 发布 GitHub Release（tag 与 zipUrl 一致），**versionCode 必须递增**
   （否则已装用户收不到更新——v3.5.9-r1 教训：同 code 覆盖发布无效）。
6. 更新 `update.json`：顶层 version/versionCode/zipUrl/sha256/updateMessage。
   **管理器显示的文字来自 `changelog` 字段指向的 `CHANGELOG.md`**（v3.5.9-r2 教训：
   只改 updateMessage 而 CHANGELOG 不更新，用户看到的一直是旧公告）。
7. 同步仓库 master：common.sh、ota-detection.sh、customize.sh、module.prop、post-fs-data.sh、
   service.sh、v351-safety.sh、features-v35.sh、action.sh、integrity.sh、
   watchdog.sh、uninstall.sh、webroot/、native/、RELEASE-NOTES、CHANGELOG、README、DEVELOPER、tests/。
8. 核对线上一致性：update.json sha256 == Release 资产 sha256 == 本地 ZIP sha256。

## 7. 测试方法（离线）

- 语法：`sh -n` 全部脚本；`node --check` WebUI JS。
- 状态机：`audit/rescuex-3.5.10/tests/` 下有离线状态机测试
  （DRY_RUN 超时、已验证救砖提交、service 超时、更新队列存在等场景）。
- 完整性动态清单：模拟有/无 WebUI 文件两种目录，调用
  `integrity_target_files` 断言输出。
- 按键默认分支：无 getevent 环境直接返回"安装 WebUI"。
- OTA r3 回归：运行 `sh tests/ota_detection_test.sh`、
  `sh tests/persistence_test.sh`、`sh tests/r3_release_metadata_test.sh`；覆盖构建基线、
  手动保护、兼容兜底、SUCCESS 提交顺序及持久化恢复。
- 安装包：运行 `python3 tests/package_layout_test.py RescueX-vX.zip`，确认无
  `webroot/state/`、tests 或历史 ZIP 混入。
- 实机验证（需社区）：安装、音量键选择、无 WebUI 模式改配置、模块更新不误重启、
  救砖触发与恢复；同时覆盖 A/B OTA、非 A/B/Recovery OTA、厂商大版本升级和手动 OTA 保护。

## 8. 已知边界

- 系统 OTA 的构建身份比较不需要厂商临时标记，但仍需要真实设备覆盖 A/B、
  Recovery/非 A/B 与 OEM 大版本更新路径；不支持的客户端可使用一次性手动保护。

- 原生看门狗（`WATCHDOG_ENGINE=native`）需 Android NDK 交叉编译，
  内置 arm64 二进制仅在设备自检通过后启用；Shell 引擎为默认与兜底。
- 完整性检查是防篡改检测而非反 Root 认证；发布签名在模块外处理。
- 无 WebUI 模式通过修改 `/data/adb/rescuex_data/config.conf` 调整参数，
  修改后需重启生效；恢复 WebUI 需重装模块选择"安装 WebUI"。
- KsuWebUIStandalone（https://github.com/5ec1cff/KsuWebUIStandalone）
  为第三方开源项目，仅用于让原版 Magisk 查看模块 WebUI，与本仓库独立。
