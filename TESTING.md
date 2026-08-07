# RescueX v3.5.9 真机测试清单

## 前置
- [ ] 备用设备；已备份 boot/vendor、模块目录、重要数据。
- [ ] 已准备可用的 Root 管理器救援方式。
- [ ] 第一次安装保持 `DRY_RUN=true`。

## 非破坏性检查
- [ ] 安装成功，模块显示版本 `v3.5.9 (35009)`。
- [ ] 正常完整启动连续 3 次，没有误触发救援。
- [ ] 手动重启一次，没有增加失败计数。
- [ ] WebUI、日志、诊断导出正常；状态文件权限为 0600。
- [ ] 看门狗在 `BOOT_END` 或持续健康信号后退出。
- [ ] patch flag 在 TTL 到期后自动清理，不永久屏蔽普通失败判定。
- [ ] 将 `rescued_disabled.list` 暂时移走后，自动恢复被拒绝，其他模块的 `disable` 文件未改变。
- [ ] 日志中不出现自动 `reboot,recovery`、`sysrq-trigger` 或 package-restrictions 删除。
- [ ] 跨 Root 事务：同名测试模块同时存在于两个模块根目录时，恢复仅移除 RescueX 当前事务实际写入一侧的 `disable`；另一侧预先存在的 `disable` 必须保留。

## 受控破坏性测试（仅在可救援环境，且先人工关闭 DRY_RUN 后）
- [ ] 单一测试模块：嫌疑模块禁用只影响该模块。
- [ ] 多模块：白名单模块绝不被禁用。
- [ ] 快照：创建、恢复、损坏快照拒绝恢复。
- [ ] 并发：打开 WebUI 操作时触发救援，第二个高风险动作被事务锁拒绝。
- [ ] 补丁：有可信快照时可回滚；无快照时仅记录人工复核，不改动模块。
- [ ] Level 2：确认只记录 `MANUAL_CONFIRM_REQUIRED`，不删除 Package Manager 文件。
- [ ] 分别在 Magisk、KernelSU/SukiSU、APatch 验证：事务状态可读；只有明确确认的恢复操作才会移除 RescueX 自己写入的 `disable`；路径变化时显示部分恢复而非猜测性启用。

## 反馈资料
提交前请保留：`rescue.log`、`rescue_audit.log`、`boot_history`、`boot_status`、`rescue.plan/commit/rollback` 和设备/Root 管理器/Android 版本信息。请脱敏后再分享。
