# RescueX v3.4.0

## 重点变更
- 彻底移除高风险脚本扫描、自动拦截、隔离、风险告警和脚本目录锁定，避免 TypeScript/JavaScript 等正常代码被误报。
- 无可靠恢复清单时 fail-closed，不会恢复所有被禁用模块。
- 自动 APP 解冻已禁用；不删除 Package Manager 限制文件。
- 保留救砖事务锁、补丁 TTL、保守重启和完整性人工复核。

## 验证
发布前已执行离线安全回归、Shell/JS 语法和安装包完整性检查；真机兼容性仍以 TESTING.md 为准。
