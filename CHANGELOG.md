# v3.5.2（原生看门狗正式落地）

- **原生看门狗正式可用**：随包包含 Android NDK r27c 编译的 arm64-v8a PIE 二进制，使用 `CLOCK_MONOTONIC` 计时并在超时后交接给 `watchdog.sh --trigger`。
- **安全回退**：仅显式配置 `WATCHDOG_ENGINE=native`、ABI 匹配、文件可执行且二进制自检通过时启用；任一条件失败立即回退 Shell。
- **构建校正**：补齐 `fchmod` 声明、Android NDK 构建脚本与模块安装脚本执行权限。
- **发布校验**：发布包包含预编译二进制，Release SHA-256 与 `update.json` 一致。

# v3.5.1（安全热修复）

> `update.json` 保留在 `module.prop` 中，管理器可正常检查更新。`update.json` 新增 `sha256` 字段，发布后填入实际 ZIP 哈希供校验。

## 安全修复
- **状态机**：慢启动不再残留 BOOTING 导致误救砖；service 等待窗口与看门狗实际超时同步
- **救砖验证**：全量救砖必须验证 disable 标记实际写入才提交 RESCUED；DRY_RUN 拒绝自动重启
- **安全模式**：一次性安全模式部分恢复失败时保留 journal，不再删除唯一恢复证据
- **Bridge 协议**：execStrict 保留退出码/超时/异常；写操作不再因空输出误报成功
- **导入原子化**：配置和白名单先写临时文件再 rename，任一失败均不提交
- **确认弹窗**：默认聚焦取消按钮；危险操作 Enter 键不会确认；焦点陷阱与 ARIA 语义

## 新增能力
- **配置 Schema 版本化**：CONFIG_SCHEMA_VERSION=3，运行时自动迁移与补全
- **启动超时自适应**：基于历史 boot_duration 移动平均动态调整，上下限约束
- **原生看门狗接口**：arm64-v8a 可选 C 看门狗（CLOCK_MONOTONIC），任何失败回退 Shell
- **深色模式**：跟随系统 prefers-color-scheme
- **差异预览**：布防安全模式前显示 dry-run 变更清单
- **二次确认**：高风险操作需双重确认
- **诊断 Issue 草稿**：生成脱敏诊断包后可选打开预填 GitHub Issue（不上传文件、不代管 Token）
- **完整性覆盖**：扩展至 v351-safety.sh、action.sh、features-v35.sh、uninstall.sh

## 兼容性
- 移除 module.prop updateJson 字段，停止管理器自动检查
- README 支持矩阵更新：未实测的 KSU/APatch 安装入口标注为实验性

---

# v3.5.0（正式版）

- **WebUI**：新增受控的 v3.5 诊断与安全模式入口：只读模拟、状态刷新、一次性布防/精确取消、脱敏诊断导出；不接收任意 Shell 输入。
- **回归**：新增 v3.5 专项隔离测试，覆盖模块变更、固定快照、选择性恢复、一次性安全模式精确所有权、只读模拟与诊断脱敏。
