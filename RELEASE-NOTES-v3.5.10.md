# RescueX v3.5.10

> 本版本在 v3.5.9-r2 基础上新增安装交互与无 WebUI 模式，并继续修复/优化。

## 新增：安装时音量键选择 WebUI

- 安装/更新模块时，通过 **音量键** 选择是否安装 WebUI：
  - `[音量+]` 安装 WebUI（推荐，默认）
  - `[音量-]` 不安装（无 WebUI 模式）
  - **60 秒内无按键操作自动安装 WebUI**（默认行为，不会卡住安装流程）
- **原版 Magisk 提示**：官方 Magisk 不支持模块 WebUI。安装界面会提示可配合
  [KsuWebUIStandalone](https://github.com/5ec1cff/KsuWebUIStandalone)
  （开源独立应用，让原版 Magisk 也能查看模块 WebUI）一起使用。
- KernelSU / SukiSU / APatch / MMRL（支持 WebUI 的管理器）会正常询问安装与否。

## 新增：无 WebUI 模式

- 选择"无 WebUI 模式"后，安装器会移除 WebUI 页面文件
  （`webroot/index.html`、`script.js`、`style.css`、`workspace-v2.css`、`assets/`），
  仅保留 `webroot/state`（配置/状态）与 `webroot/arm64-v8a`（原生看门狗二进制）。
- 无 WebUI 模式下所有参数通过**直接修改配置文件**调整：
  - 配置文件：`/data/adb/rescuex_data/config.conf`（持久化，模块更新不丢失）
  - 常用项：`REBOOT_THRESHOLD`（连续重启阈值）、`BOOT_TIMEOUT_SEC`（开机超时）、
    `DRY_RUN`、`ENABLED`、`WATCHDOG_ENGINE` 等
  - 修改后需重启设备生效
- 如需恢复 WebUI：重新安装模块并选择"安装 WebUI"即可。

## 完整性检查适配

- 无 WebUI 模式下移除的页面文件不再纳入完整性基线哈希；
  完整性检查（integrity daemon）不会把缺失页面误报为 COMPROMISED 或被篡改。

## 保留的既有修复（v3.5.9-r1/r2 全部继承）

- 不再接管 Root 管理器更新队列（`modules_update` 不再被移动/回放/重启）。
- `BOOT_TOKEN` 仅用于诊断与事务归属，不再单独触发救砖判定。
- 默认 `DRY_RUN=true`，需用户显式确认后才执行实际救砖。
- 启动统计完整性校验（成功率不再超过 100%）。
- service 终态（RESCUED）保护；事务 journal 精确恢复。

## 版本元数据

- version: v3.5.10
- versionCode: 35020

## 验证

- POSIX shell 语法检查全部通过（sh -n）。
- JavaScript 语法检查通过。
- 安装交互超时逻辑：无按键时 60 秒后自动进入"安装 WebUI"分支。
- 完整性基线：无 WebUI 模式（移除页面后）可正常建立基线。
