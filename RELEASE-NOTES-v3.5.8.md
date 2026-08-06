# RescueX v3.5.8 — 跨 Root 救砖事务恢复中心

## 重点更新

- **跨 Root 精确恢复**：救砖事务现在记录管理器类型、模块根目录、实际模块路径和由 RescueX 写入的 `disable` 标记。恢复只移除当前事务中可验证属于 RescueX 的标记，不会按模块 ID 跨 Magisk、KernelSU/SukiSU、APatch 扫描或重新启用用户手动禁用的模块。
- **可恢复的事务状态**：事务写入前先持久化目标 journal；路径消失、根目录变更或标记无法验证时返回 `PARTIAL` 并保留证据，允许人工复核，而非猜测性恢复。
- **CLI 管理**：新增 `action.sh --cli rescue status` 查询当前事务；执行恢复必须使用 `action.sh --cli rescue restore --apply` 明确确认。
- **WebUI 安全恢复**：原“恢复全部模块”入口改为事务绑定恢复，并显示当前事务状态；APatch bridge 可用时可进入 WebUI，实际模块路径仍由 Shell 后端统一识别。
- **APatch 状态识别**：CLI 即使没有预设 `APATCH=true`，也会通过标准 APatch 模块目录识别当前环境。

## 安全与兼容性

- 旧版仅包含模块 ID 的 `rescued_disabled.list` 不再用于跨 Root 自动恢复，因为它无法验证具体路径归属；缺少 v3.5.8 事务证据时恢复会安全拒绝。
- 新事务兼容 Magisk、KernelSU、SukiSU Ultra 与 APatch 的标准模块目录。实际刷入和 Root 管理器 WebUI 仍需在对应备用设备执行 `TESTING.md`。

## 发布文件

- `RescueX-v3.5.8.zip`
- `RescueX-v3.5.8.zip.sha256`
