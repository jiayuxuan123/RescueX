# RescueX v3.5.9 — 当前版本

> **📦 项目当前处于休眠状态**
>
> 这是 RescueX 的当前稳定版本。历经 30+ 次迭代、覆盖多轮实机验证，核心救砖功能已完整稳定。
> 当前停止活跃维护，后续如有新的想法或需求，可能会重启项目开发。
>
> - 代码保持开源（MIT），可自由使用与 fork
> - GitHub Release 保留下载链接
> - Issue 可能不会及时回复；如需继续维护，建议 fork 自行开发
>
> ---

## 本版本修复

- 修复 Android 早期启动时 RTC 尚未可用、`BOOT_START=0` 导致真实连续重启被提前当作「非失败」的问题
- 现在优先比较内核 `BOOT_TOKEN`：只要上一轮未完成且 token 已变化，即使墙钟尚未同步也会计为真实失败
- 保留 token 缺失或相同 token 时的保守 RTC/用户主动重启宽限逻辑，避免扩大误判范围
- 当渐进救砖开启时，满足该失败条件会进入三级救砖：第 0 级无法定位嫌疑模块时自动落到第 1 级，写入已验证的模块 `disable` 标记并提交 `RESCUED` 状态

## 验证

- 新增 `tests/early_boot_rescue_test.sh`，覆盖实机同类状态：`BOOT_START=0`、未完成启动、不同 `BOOT_TOKEN`，验证进入第 1 级并提交 `RESCUED`
- `tests/test_safety.sh` 全部通过（17 项安全测试）
- 新版 WebUI 协议公告 revision 为 `r4`，同版本也会重新弹出，阅读倒计时为 8 秒

## 下载

- ZIP：https://github.com/jiayuxuan123/RescueX/releases/download/v3.5.9/RescueX-v3.5.9.zip
- SHA-256：`ca844f6982b88ea972a8dab960608b5f176d24e93dc0f0be00d579f2aa9bbf1f`

## 其他版本

如需旧版本，请前往 [Releases 页面](https://github.com/jiayuxuan123/RescueX/releases) 查看历史版本。
