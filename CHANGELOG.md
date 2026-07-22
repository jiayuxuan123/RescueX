## v3.3.0-r3 (2026-07-22)

### Fixed

- **启动状态判定修复**：启动完成属性未确认时保留 `BOOTING` 状态，让看门狗继续负责超时救砖。
- **守护进程生命周期修复**：看门狗不再以 `SERVICE_STARTED` 提前退出，完整性守护支持启动锁和卸载停止。
- **补丁回滚修复**：补丁失败计数覆盖 service 已启动后崩溃场景，并在设置补丁标记时保存补丁前快照。
- **更新回放安全修复**：模块更新回放失败时保留备份并恢复旧模块，支持失败后重试。
- **WebUI 稳定性修复**：修复配置开关、模块切换结果判断、快照删除结果判断、自定义目录临时文件清理和更新请求超时。
- **完整性校验增强**：拒绝空基线，补充哈希条目数量校验，并新增全量发布检查脚本和回归测试。

## v3.3.0-r2 (2026-07-22)

### Fixed

- **完整性按钮修复**：补齐 WebUI 事件白名单中的 `runIntegrityCheck`，立即检查完整性按钮现在会执行后端校验并刷新状态。
- **更新可见性修复**：通过独立的 `v3.3.0-r2` 版本和 `versionCode=33002`，让已安装 `v3.3.0-r1` 的 Root 管理器识别到修复版更新。

## v3.3.0-r1 (2026-07-22)

### Fixed

- **隐藏环境模块兼容性修复**：提高版本号至 `33001`，允许模块在自身目录内部清理深层工作目录、缓存和临时文件，继续拦截模块目录本身的删除。
- **更新可见性修复**：通过独立的 `v3.3.0-r1` 版本和安装包，让已安装 `v3.3.0` 的 Root 管理器识别到修复版更新。

## v3.3.0 (2026-07-22)

### 安全与完整性

- **轻量完整性自检**：新增默认开启的完整性自检守护，首次成功启动后建立核心脚本 SHA-256 基线，并按随机间隔周期校验。
- **完整性状态管理**：WebUI 新增完整性自检状态、守护进程状态、最近检查时间和立即检查入口。
- **破坏性脚本误报修复**：普通 `/data` 私有工作目录和 `/data/adb` 私有目录的清理操作不再被误判为擦除分区。
- **隐藏环境模块兼容性修复**：允许模块在自身目录内部清理深层工作目录、缓存和临时文件，继续拦截模块目录本身的删除。
- **高风险路径分级拦截**：继续拦截 Android 核心数据根、模块根、共享存储，以及明确的格式化、擦除和块设备写入命令。
- **回归验证**：增加破坏性脚本判定的回归样例，覆盖放行路径、核心路径和格式化命令。

## v3.2.9 (2026-07-19)

### Fixed
- **MMRL 重入保护**：`action.sh` 在前台已经是 MMRL 时不再二次拉起 MMRL 的 `WebUIActivity`，降低部分设备上的前台重入崩溃概率。

## v3.2.8 (2026-07-19)

### Fixed
- **审计修复汇总**：修复决策报告状态读取、脚本隔离与恢复、启动模式误判、补丁更新误报和 WebUI 动作白名单。

## v3.2.7-alpha (2026-07-18)

### Fixed
- **状态展示一致性**：CLI、WebUI 和 module.prop 对嫌疑模块、状态变化嫌疑、已知良好基线的展示口径保持一致。
- **看门狗状态判断**：WebUI 仪表盘使用更严格的 cmdline 匹配，避免误把其他进程显示为 RescueX 看门狗。
- **隐私提示修复**：诊断报告生成前提示敏感信息范围，隐私协议同步说明检查更新的 GitHub 网络访问。
- **文档结构修复**：修复英文使用说明中的 HTML 列表闭合错误。

## v3.2.6-alpha (2026-07-18)

### Fixed
- **WebUI 检查更新跳转修复**：检测到新版本后不再尝试打开二进制 zip 直链（WebView 不支持），改为跳转 GitHub Releases 页面手动下载。

## v3.2.6 (2026-07-18)

### Fixed
- **删除型持久化状态一致性**：`patch_update_flag`、`rescued_disabled.list`、`auto_snapshot_session` 这类以“文件存在/删除”表达状态的数据，在运行态删除后会同步清理持久化副本。
- **持久化镜像收敛**：持久化同步会主动移除当前状态目录里已经不存在的删除型状态文件，避免历史残留在后续恢复时反灌回来。

## v3.2.5 (2026-07-18)

### Fixed
- **移除代理更新链路**：仓库、Releases、在线更新元数据和下载地址恢复为 GitHub 直连，避免代理跳转后的跨域和二次跳转错误。

## v3.2.4 (2026-07-18)

### Fixed
- **删除后不再复活**：手动删除快照时会同步清理持久化目录中的副本，模块升级或恢复后不会再次出现。
- **持久化快照收敛**：持久化同步时会清理已经不存在于当前快照目录中的旧文件，避免历史残留持续回流。

## v3.2.3 (2026-07-18)

### New Features
- **检查更新按钮**：WebUI 新增一键检查更新，可直接比对远端 `update.json` 并跳转下载。

### Improvements
- **代理访问统一**：GitHub 仓库、Releases 和在线更新元数据统一走 `https://gitjs.yunluo.de5.net/` 代理。
- **手动快照保留收紧**：手动快照统一只保留最新 5 份。

### Fixed
- 历史版本把自动快照误存成 `snap-*.txt` 后，诊断报告和快照列表会将其当成手动快照展示的问题。

## v3.2.2 (2026-07-18)

### New Features
- **GitHub 开源入口**：WebUI 新增仓库地址与 Releases 入口，便于直接查看源码和新版包。
- **更新公告卡片**：WebUI 新增当前版本更新公告，集中展示本版变化。
- **在线更新配置**：模块元数据新增 `updateJson`，可通过 GitHub Release 提供在线更新。

### Improvements
- **自动快照会话去重**：同一轮启动只生成一次自动快照，避免失败启动时重复覆盖与频繁写入。
- **手动快照保留收敛**：手动快照统一只保留最新 12 份，迁移和持久化恢复后同样会自动裁剪。

### Fixed
- 失败启动链路内多次进入救砖逻辑时重复生成自动快照。
- 损坏快照中的非法状态值参与恢复的问题。

## v3.2.0 (2026-07-17) - Formal Release

### New Features
- **High-risk script interception**（实验性，未在真实设备上充分测试）：Auto-scans module entry points (post-fs-data.sh, service.sh, etc.) for destructive wipe/format commands. Offending modules are disabled or script files locked immediately, with root notifications sent after boot completes.
- **Unified dashboard snapshot**: Frontend status panel and stats panel now share a single `get_dashboard_snapshot()` backend call, eliminating stale/divergent numbers from separate data sources.
- **MMRL compatibility**: Updated update-cache handling for MMRL directories, with UI manager detection distinguishing SukiSU Ultra (MMRL) and KSU (MMRL).
- **SukiSU Ultra recognition**: Manager detection now recognizes SukiSU Ultra as a KernelSU-compatible variant with proper UI display and launcher handling.
- **Baseline restore**: One-click restore of last stable (known-good) module baseline from the WebUI.
- **Rescue decision report**: Generates a structured text report of rescue decisions, module states, and boot statistics.
- **Snapshot retention optimization**: Automatic snapshots now overwrite a single rolling file, while user-triggered snapshots remain individually preserved.
- **Subtle easter eggs**: Lightweight UI easter eggs accessible via logo icon taps and rapid language switching.

### Improvements
- **Boot stats accuracy**: Rescue count now sourced from `boot_history` RESCUE entries, not from audit log line count. This fixes over-counting that inflated rescue numbers.
- **Suspect module pruning**: Stale suspect-module log entries are pruned when the corresponding module is removed.
- **Boot trend compact view**: Chart limited to the most recent 9 successful boot entries.
- **OTA handling enhancement**: Added `modules_update` backup/replay flow during OTA upgrades.
- **Version sweep**: All version strings unified to `v3.2.0` / `32000` across module metadata, scripts, and WebUI.

### Fixed
- Rescue count showing `28` in status panel but `3` in stats panel due to separate data queries.
- `LAST_RESCUE_TIME` showing "never" when rescue count was non-zero.
- Custom directory permission bypass for unsafe system paths.

## v3.1.1-beta.1 (2026-07-17) - Beta

### New Features
- **Readiness panel**: WebUI now shows rescue readiness score with actionable warnings.
- **Safer custom directories**: Custom directory permissions restricted to RescueX-owned prefixes only.
- **Audit logging**: Manual actions (patch flag, snapshot ops, baseline changes) are logged to rescue audit.
- **WebUI action routing**: High-risk actions like snapshots and restores routed through common.sh shared functions.

## v3.1.0 (2026-07-16)

- Initial structured module implementation with:
  - Three-level progressive rescue
  - Boot timeout watchdog
  - Suspect module tracking
  - OTA-aware timeout adjustment
  - WebUI for management (compatible with KSU / Magisk v27+ / MMRL)
