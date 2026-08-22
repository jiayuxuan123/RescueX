# v3.5.10-r3（跨厂商系统 OTA 检测与升级可靠性修复）

> **需要不同 ROM 社区用户参与验证。** 本版以最近一次确认成功启动的系统构建基线识别 OTA 与厂商 Android 大版本更新，并保留旧 OTA/Recovery/BCB/update_engine 信号作兼容兜底；无法自动识别时可设置一次性手动 OTA 保护。

- 新增 `ota-detection.sh`：比较 build/system/vendor/product/bootimage 指纹、增量版本、安全补丁、API/Android 版本、构建 ID 和 A/B 槽位，任一可信变化均使用 OTA 长超时。
- 基线只会在 `service.sh` 已提交 `SUCCESS` 后推进；新系统未成功启动时保留旧基线，使后续重试继续享有 OTA 长超时。
- WebUI 和 CLI 展示检测来源；`ota arm --apply` 可为不兼容 OEM 更新客户端设置一次性保护，成功启动后自动清除。
- 修复结构化 patch flag 在 WebUI 的读取/清除、v35 状态恢复、启动时长历史持久化、WebUI `DRY_RUN=true` 默认值和 CLI 第三参数转发。
- 离线 OTA/持久化/元数据测试 15 项、全部 Shell 语法检查和 WebUI JS 语法检查通过；尚需 A/B、非 A/B/Recovery OTA、OEM 大版本升级和手动保护的真实设备报告。
- 版本：v3.5.10-r3 / versionCode 350203。

# v3.5.10-r2（启动统计按终态重构：救砖正确反映 + 最近救砖时间修复）

> **推荐所有 RescueX 用户更新。** 治本修复两大统计问题：救砖后成功率不再永远 100%；最近救砖不再显示"从未"。

- 成功率修复：postfs 救砖不写 START 行导致救砖启动不进统计分母 → 现按 boot token 终态聚合，RESCUE/FAILURE 行也计为一次启动（失败终态）；孤儿 SERVICE 行不计入；重复行去重。
- 最近救砖修复：早期 RTC 时 LAST_RESCUE_TIME=0 且 fix 跳过 0、postfs 用旧值覆盖、统计丢弃 uptime 时间 → fix 允许 0+已救砖时修正为当前时间；fix 移到 read_previous_status 之前；commit 保留旧时间；统计回退状态文件时间。
- 救砖次数下限补偿：max(历史 RESCUE 行, status RESCUE_COUNT)。
- 离线验证 7 场景全通过（含 3 次救砖 → 4/7=57%）。
- 版本：v3.5.10-r2 / versionCode 350202。

# v3.5.10-r1（启动统计治本修复：配对计数）

> **推荐所有 RescueX 用户更新。** 修复成功率虚高：此前成功次数按所有 SERVICE 行统计，历史孤儿行（无对应 START）导致成功数超过总启动数，钳制后成功率永远 100%，救砖也不下降。本版改为配对计数，救砖/失败会正确反映在成功率上。

- 成功次数只统计「boot token 能配对到 START 行」的 SERVICE 行；孤儿行不计入，重复行只计一次。
- 离线验证 5 场景：正常 100%、脏数据孤儿不计、含救砖 80%、重复行只计一次、老格式兼容。
- 版本号规则调整：主版本 v3.5.10 = 35020；同级修复用 `-rN` 后缀，versionCode 为 `350201`、`350202`… 不再跳主版本号。
- 继承 v3.5.10 全部功能（音量键 WebUI 选择、无 WebUI 模式）与 v3.5.9-r1/r2 全部修复。

# v3.5.10（安装交互：音量键选择 WebUI / 无 WebUI 模式）

> **推荐所有 RescueX 用户更新。** 新增安装时音量键选择是否安装 WebUI；60 秒无操作自动安装 WebUI；原版 Magisk 提示可配合 KsuWebUIStandalone 使用；支持无 WebUI 模式（直接修改配置文件）。

- 安装时按 **音量+** 安装 WebUI，**音量-** 不安装；60 秒无操作自动安装 WebUI。
- 原版 Magisk 不支持 WebUI，安装界面提示可配合开源应用 [KsuWebUIStandalone](https://github.com/5ec1cff/KsuWebUIStandalone) 使用。
- 无 WebUI 模式自动移除 WebUI 页面文件（保留 `webroot/state` 配置与 `webroot/arm64-v8a` 原生看门狗），所有参数可直接修改 `/data/adb/rescuex_data/config.conf` 后重启生效。
- 完整性检查适配：无 WebUI 模式下移除的页面文件不再纳入完整性基线，不会误报 COMPROMISED。
- 继承 v3.5.9-r1/r2 全部修复：更新队列隔离、BOOT_TOKEN 仅诊断、DRY_RUN 默认开启、启动统计完整性校验。
- 版本元数据：v3.5.10 / versionCode 35020。

# v3.5.9-r2（启动统计完整性修复）
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
