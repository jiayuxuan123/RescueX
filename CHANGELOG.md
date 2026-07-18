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
