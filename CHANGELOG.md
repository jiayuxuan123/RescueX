# v3.5.9-r2（启动统计完整性修复）

> **推荐所有 RescueX 用户更新。** 修复 WebUI 启动统计异常（成功率超过 100%），并干净重打包。已安装 v3.5.9-r1（versionCode 35010）的设备可通过正常更新通道收到此版本。

- 修复 `compute_boot_stats` 统计完整性：`boot_history` 重复条目可能导致 SUCCESS > TOTAL（如 4 次启动显示 7 次成功 / 175%），现在钳制 SUCCESS ≤ TOTAL 并记录警告日志。
- 保留 v3.5.9-r1 全部安全修复：不再接管 Root 管理器更新队列（`modules_update` 不再被移动/回放/重启）；`BOOT_TOKEN` 仅用于诊断与事务归属，不再单独触发救砖；默认 `DRY_RUN=true`。
- 移除 r1 包中误带的 `Users/Administrator/.../handoff` 路径条目。
- 版本元数据：v3.5.9-r2 / versionCode 35011。

# v3.5.9-r1（归档修复版：更新队列劫持与误救砖）

- RescueX 不再移动、回放或重启 Root 管理器的 `modules_update` 更新队列，安装/更新其他模块不再触发误重启。
- 失败判定保守化：`BOOT_TOKEN` 变化降级为诊断证据，不再单独触发渐进式救砖。
- `DRY_RUN` 默认开启，需用户显式确认后才执行实际救砖。

---

# v3.5.9（强烈推荐更新：启动救砖底层严重漏洞修复）

> **强烈推荐所有 v3.5.x 用户立即更新。** 本版本修复一个底层安全可靠性漏洞：早期 Android 启动 RTC 尚未同步时，旧版可能跳过连续重启失败判定，导致三级自动救砖不触发。

- 现在优先比较内核 `BOOT_TOKEN`；未完成启动且 token 变化会直接计入失败并进入渐进式三级救砖。
- 第 0 级无法定位嫌疑模块时会按设计落到第 1 级，验证 `disable` 标记后提交 `RESCUED`。
- 新增实机同类状态回归：`BOOT_START=0 + 不同 BOOT_TOKEN` 会进入第 1 级并提交 `RESCUED`。
- 更新公告与新版协议会在 v3.5.9 首次进入 WebUI 时重新显示，阅读倒计时缩短为 8 秒。

# v3.5.8（跨 Root 救砖事务恢复中心）

- 新增跨 Root 救砖事务 journal：每个禁用目标记录 Root 管理器、模块根目录、模块路径、实际 `disable` 标记和标记归属。
- 恢复操作仅处理 RescueX 当前事务实际写入且仍可验证路径归属的标记；同名模块位于 Magisk、KernelSU/SukiSU、APatch 的不同根目录时不会被误启用。
- 路径变更、模块消失或标记无法验证时保留事务并报告 `PARTIAL`，不进行猜测性恢复。
- `action.sh --cli rescue status` 可查询事务；`action.sh --cli rescue restore --apply` 必须显式确认才会恢复。
- WebUI 将“恢复所有模块”改为事务绑定恢复，并增加事务状态查询；APatch bridge 可用时被识别，CLI 的 APatch 检测加入标准目录回退。
- 发布 ZIP 明确排除设备运行时状态，新增跨 Root 同名模块精确恢复回归测试。
