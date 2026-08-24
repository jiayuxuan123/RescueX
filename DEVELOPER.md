# RescueX 开发者接手文档

> 本文档面向后续维护者与 AI Agent，说明 RescueX 的架构、关键决策、发布流程与测试方法。
> 项目采用 MIT 开源协议，欢迎 fork 与改进。

## 1. 项目概览

RescueX 是一个 Magisk / KernelSU / APatch 模块，用于**自动救砖**：
监控启动失败次数与开机超时，在确认持续无法进入系统时，按三级策略逐步
（嫌疑模块禁用 → 验证式全量禁用 → 日志审计）恢复设备。

- 仓库：`jiayuxuan123/RescueX`（GitHub）
- 当前版本：v3.5.11（versionCode 350204）
- 兼容：Android 9+ (API 28+)，Magisk 20.4+ / KernelSU / APatch / SukiSU / MMRL

## 2. 目录结构与职责

| 路径 | 职责 |
| --- | --- |
| `module.prop` | 模块元数据（id/version/versionCode/updateJson） |
| `customize.sh` | 安装/更新脚本：API 检查、管理器检测、WebUI 安装选择与持久化、配置迁移、权限设置 |
| `webui-choice.sh` | WebUI 安装偏好状态库：待确认/暂缓/已确认、安装器文案语言（默认中文）、locale/timezone 和原子写入 |
| `monet-palette.sh` | 莫奈取色读取器：用 root 权限通过 `cmd overlay lookup` 读取系统已生成的 Material You 色阶（只读） |
| `common.sh` | 核心库：路径/状态/配置/历史/统计/完整性/救砖状态机（被所有脚本 source） |
| `ota-detection.sh` | 跨厂商系统 OTA 检测：成功启动构建基线、厂商活动更新信号兜底、一次性手动保护与诊断状态 |
| `post-fs-data.sh` | 开机早期阶段：启动模式检测、失败判定、看门狗启动、状态写入 |
| `service.sh` | 系统服务阶段：等待启动完成、提交 SUCCESS、完整性守护启动 |
| `watchdog.sh` | 看门狗：按配置轮询启动进度，超时执行救砖 |
| `integrity.sh` | 完整性守护进程：周期性哈希核心文件，检测被篡改 |
| `v351-safety.sh` | v3.5.1 安全层（**最后加载**）：fail-closed 状态机、救砖事务 journal、动态完整性清单 |
| `features-v35.sh` | v3.5 功能层：一次性安全模式、模块变更扫描、健康时间线 |
| `action.sh` | CLI 入口：`action.sh --cli rescue status/restore` 等 |
| `uninstall.sh` | 卸载清理 |
| `native/rescuex_watchdog.c` | 可选原生看门狗（默认 Shell 引擎，原生需显式 `WATCHDOG_ENGINE=native`） |
| `webroot/` | WebUI 页面（index.html/script.js/style.css/workspace-v2.css/md3-theme.css + `state/` 状态目录 + `arm64-v8a/` 原生二进制） |
| `META-INF/com/google/android/update-binary` | 标准 Magisk 安装引导 |

## 3. 关键数据位置

| 路径 | 内容 |
| --- | --- |
| `$MODDIR/webroot/state/` | 模块内状态目录：`config.conf`、`whitelist.conf`、`boot_status`、`boot_history`、`rescue.log`、快照、完整性基线等 |
| `/data/adb/rescuex_data/` | **外部持久化镜像**（模块更新/卸载不丢失）：config、历史、统计、完整性基线的备份 |
| `/data/adb/rescuex_data/config.conf` | **无 WebUI 模式下用户手动修改的配置文件**（模块内 state 有同内容副本，运行时以 state 为准，启动时从持久化恢复缺失项） |
| `/data/adb/rescuex_data/ota_build_baseline` | 上一次确认成功启动的系统构建身份，用于跨厂商 OTA / 大版本升级识别 |
| `/data/adb/rescuex_data/ota_update_pending` | 用户明确设置的一次性 OTA 长超时保护；仅在成功启动后自动清除 |
| `/data/adb/rescuex_data/webui_install_preference` | WebUI 安装偏好；确认后更新自动沿用，未确认时只在安装阶段监听音量键 |

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
8. **跨厂商 OTA 检测按成功构建基线判断**：旧临时文件/属性仅作兼容兜底；
   基线只能在 service 已提交 `SUCCESS` 后推进，失败启动不得覆盖旧基线。

## 5. 安装交互（v3.5.10）

`customize.sh` 在安装/更新时：

1. 检测管理器：KernelSU / SukiSU / APatch / Magisk / 未知。
2. 若 `/data/adb/rescuex_data/webui_install_preference` 已有 `STATE=CONFIRMED`，自动沿用 `CHOICE=install/skip`，不再监听音量键。
3. 没有确认记录时才显示中英文 WebUI 选择：
   - `[音量+]` 安装 WebUI
   - `[音量-]` 暂不安装 WebUI
   - **60 秒无按键自动安装 WebUI**（`wait_webui_volkey()`，无 getevent 环境直接默认）
4. 首次明确选择安装 WebUI 后，第一次进入 WebUI 会询问是否持久化；可选择自动安装、自动跳过或暂不决定。
   升级时若检测到已有 WebUI，误按音量下不会立即删除页面，需在 WebUI 中确认最终偏好。
5. 原版 Magisk（无 KSU/APATCH 环境、未检测到 MMRL）：提示可能不支持 WebUI，并给出 [KsuWebUIStandalone](https://github.com/5ec1cff/KsuWebUIStandalone) 下载地址。
6. 确认的无 WebUI 模式删除：`webroot/index.html`、`script.js`、`style.css`、
   `workspace-v2.css`、`md3-theme.css`、`assets/`；保留状态、`webui-choice.sh`、`monet-palette.sh` 和原生看门狗。

## 6. 发布流程（新版本）

1. 在 `audit/rescuex-3.5.10`（工作副本）改代码；**原始 ZIP 归档不动**。
2. 版本统一 bump：`module.prop`、`common.sh`（RX_VERSION/RX_VERSION_CODE）、
   `customize.sh`（RX_VERSION）、`webroot/script.js`（APP_VERSION/APP_VERSION_CODE）、
   `webroot/index.html`、RELEASE-NOTES、CHANGELOG。
3. 校验：`sh -n` 全部脚本 + `node --check webroot/script.js`。
4. 打包：`zip -r -X RescueX-vX.zip . -x "*.zip"`（确认无 `.git`/临时文件混入）。
5. 发布 GitHub Release（tag 与 zipUrl 一致），**versionCode 必须递增**
   （否则已装用户收不到更新——v3.5.9-r1 教训：同 code 覆盖发布无效）。
6. 更新 `update.json`：顶层 version/versionCode/zipUrl/sha256/updateMessage。
   **管理器显示的文字来自 `changelog` 字段指向的 `CHANGELOG.md`**（v3.5.9-r2 教训：
   只改 updateMessage 而 CHANGELOG 不更新，用户看到的一直是旧公告）。
7. 同步仓库 master：common.sh、customize.sh、module.prop、post-fs-data.sh、
   service.sh、v351-safety.sh、features-v35.sh、action.sh、integrity.sh、
   watchdog.sh、uninstall.sh、webroot/、native/、RELEASE-NOTES、CHANGELOG、README、DEVELOPER。
8. 核对线上一致性：update.json sha256 == Release 资产 sha256 == 本地 ZIP sha256。

## 7. 测试方法（离线）

- 语法：`sh -n` 全部脚本；`node --check` WebUI JS。
- 状态机：`audit/rescuex-3.5.10/tests/` 下有离线状态机测试
  （DRY_RUN 超时、已验证救砖提交、service 超时、更新队列存在等场景）。
- 完整性动态清单：模拟有/无 WebUI 文件两种目录，调用
  `integrity_target_files` 断言输出。
- OTA 检测：模拟无基线、构建身份/槽位变化、厂商易失属性/近期状态文件信号、常驻与过期信号被忽略、手动保护、旧信号回退和损坏基线；
  验证只有成功提交后才更新系统构建基线。
- WebUI 偏好：验证待确认、暂缓、确认、损坏记录 fail-closed、locale/timezone 和原子写入。
- 安装器语言：验证中文为默认（含无可读 locale 的 recovery 环境）、中文变体均归为中文、外语环境用英文，以及三行音量键提示在任何语言下都是中英双语。
- 莫奈取色：以 stub 模拟 `cmd overlay lookup`，验证优先使用系统真实色阶、剔除 alpha、降级种子色会被标记为近似、无可读源时 fail-closed，以及读取器不写入任何系统状态。
- 导航：验证分组隐藏样式存在，以保证手机底部导航可以真正切页。
- UI：验证 MIUI X/MD3 主题资源均存在、主题偏好可持久化、文档长路径在窄屏可换行。
- 按键默认分支：无 getevent 环境直接返回"安装 WebUI"。
- 实机验证（需用户）：安装、音量键选择、无 WebUI 模式改配置、
  模块更新不误重启、救砖触发与恢复、WebUI 统计正确。

## 8. 已知边界

- 原生看门狗（`WATCHDOG_ENGINE=native`）需 Android NDK 交叉编译，
  内置 arm64 二进制仅在设备自检通过后启用；Shell 引擎为默认与兜底。
- 完整性检查是防篡改检测而非反 Root 认证；发布签名在模块外处理。
- 无 WebUI 模式通过修改 `/data/adb/rescuex_data/config.conf` 调整参数，
  修改后需重启生效；恢复 WebUI 需重装模块并确认安装偏好。
- 厂商 OTA 信号只用易失的 `sys.*` 属性和近期更新痕迹；`ro.*`/`persist.*` 状态和常驻运行的
  `update_engine` 不作为信号，避免正常安装后每次开机都被当作 OTA。
- 莫奈取色依赖 Android 12+ 的框架色资源和 `cmd overlay lookup`；旧系统或缺少该命令时
  降级为主题种子色近似，并在外观弹窗明确标注“近似配色”，不会冒充真实色阶。
- 系统 OTA 检测不依赖某个厂商客户端；无法从构建身份或兼容信号识别的更新可在重启前
  用 WebUI 或 `action.sh --cli ota arm --apply` 设置一次性保护。
- KsuWebUIStandalone（https://github.com/5ec1cff/KsuWebUIStandalone）
  为第三方开源项目，仅用于让原版 Magisk 查看模块 WebUI，与本仓库独立。
