# v3.5.8（跨 Root 救砖事务恢复中心）

- 新增跨 Root 救砖事务 journal：每个禁用目标记录 Root 管理器、模块根目录、模块路径、实际 `disable` 标记和标记归属。
- 恢复操作仅处理 RescueX 当前事务实际写入且仍可验证路径归属的标记；同名模块位于 Magisk、KernelSU/SukiSU、APatch 的不同根目录时不会被误启用。
- 路径变更、模块消失或标记无法验证时保留事务并报告 `PARTIAL`，不进行猜测性恢复。
- `action.sh --cli rescue status` 可查询事务；`action.sh --cli rescue restore --apply` 必须显式确认才会恢复。
- WebUI 将“恢复所有模块”改为事务绑定恢复，并增加事务状态查询；APatch bridge 可用时被识别，CLI 的 APatch 检测加入标准目录回退。
- 发布 ZIP 明确排除设备运行时状态，新增跨 Root 同名模块精确恢复回归测试。
