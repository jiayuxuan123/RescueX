# RescueX v3.4.3

> 正式发布构建。

## 本次更新

### Miuix 风格 WebUI
- 采用 Miuix 系统设置式浅色分组：去除黑色顶栏、雷霆/工业风装饰和高压大卡片。
- 手机端改为固定五项底部导航：概览、保护、模块、救援、日志。
- 中文 / EN 语言切换固定显示在标题右侧；320px 窄屏不会被隐藏。
- 蓝色仅用于操作和当前导航；绿色、橙色、红色仅用于安全、注意与风险状态。
- 完整性“最近检查”改为可读的相对时间，不再直接展示 Unix 时间戳。

### 完整性升级修复
- 修复正常模块升级被误报为 `REVIEW_REQUIRED` 的问题。
- 当 `versionCode` 变化时，会以当前已安装模块文件建立新版本基线；同版本文件哈希变化仍会报告 `COMPROMISED`。
- 升级仅清理旧完整性 manifest、status 与 pid，不清理用户配置、白名单、快照或启动统计。
- 安装阶段显式设置 `integrity.sh` 和 `workspace-v2.css` 权限；完整性守护通过 `sh` 启动，不受旧安装可执行位残留影响。
- 迁移旧配置时补齐 `INTEGRITY_CHECK_ENABLED=true` 与检查间隔配置。

## 回归验证
- 版本基线升级：`34020 → 34030` 返回 `BASELINE_CREATED`。
- 同版本篡改核心脚本：返回 `COMPROMISED`。
- 自检守护：PID、状态写入和停止清理通过。
- HTML、JavaScript、Shell、36 个 WebUI action、完整安装 ZIP 合同均通过。

## 发布信息
- 版本：`v3.4.3` (`versionCode 34030`)
- 安装包：`RescueX-v3.4.3.zip`
