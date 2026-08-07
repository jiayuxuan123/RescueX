# RescueX v3.5.9 — 强烈推荐更新：启动救砖底层严重漏洞修复

> **强烈推荐所有 v3.5.x 用户立即更新。** 修复早期 Android 启动 RTC 尚未同步时可能跳过连续失败判定、导致三级自动救砖不触发的底层安全可靠性漏洞。

## 修复

- 修复 Android 早期启动时 RTC 尚未可用、`BOOT_START=0` 导致真实连续重启被提前当作“非失败”的问题。
- 现在优先比较内核 `BOOT_TOKEN`：只要上一轮未完成且 token 已变化，即使墙钟尚未同步也会计为真实失败。
- 保留 token 缺失或相同 token 时的保守 RTC/用户主动重启宽限逻辑，避免扩大误判范围。
- 当渐进救砖开启时，满足该失败条件会进入三级救砖：第 0 级无法定位嫌疑模块时自动落到第 1 级，写入已验证的模块 `disable` 标记并提交 `RESCUED` 状态。

## 验证

- 新增 `tests/early_boot_rescue_test.sh`，覆盖实机同类状态：`BOOT_START=0`、未完成启动、不同 `BOOT_TOKEN`，验证进入第 1 级并提交 `RESCUED`。
- `tests/test_safety.sh` 已通过。
- 新版 WebUI 协议公告 revision 为 `r4`，同版本也会重新弹出，阅读倒计时为 8 秒。
