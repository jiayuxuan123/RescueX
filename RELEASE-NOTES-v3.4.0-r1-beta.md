# RescueX v3.4.0-r1-beta — 安全灰度包

## 发布状态
- **仅供真机灰度测试，不可直接作为稳定版发布。**
- 未上传 GitHub；GitHub Release 和 update.json 远端文件必须在测试通过后再发布。
- 首次安装默认 `DRY_RUN=true`。

## 审计问题的处理结果

| 审计项 | 本版处理 |
|---|---|
| 无清单恢复全部禁用模块 | 已删除危险实现；无清单/空清单直接拒绝恢复。 |
| 自动 APP 解冻 | 已禁用；不会删除 Package Manager 的 restriction 文件。 |
| 救砖并发 | 已增加目录锁、计划/提交/失败事务记录。 |
| 补丁回滚 | patch flag 增加 TTL；无可信快照拒绝自动回滚；失败不清计数。 |
| 看门狗 | 增加多信号健康观察；失败动作不伪造成功状态。 |
| 重启升级 | 自动路径只请求一次普通 reboot；移除 Recovery 和 SysRq。 |
| 完整性基线 | 版本不匹配进入人工复核，不自动重建。 |
| 自定义目录 | 加入 `readlink -f` 的真实路径/符号链接拒绝策略。 |
| 快照默认数 | 统一为 12。 |

## 已完成的离线验证

- 7 项安全回归测试；
- 全部 shell 入口 `sh -n`；
- WebUI `node --check`；
- 静态确认不含自动 Recovery、SysRq、删除 package-restrictions、全量恢复禁用模块路径；
- ZIP 完整性和内容白名单检查。

## 未完成的验证

必须在真机完成 Android 版本、Magisk / KernelSU / APatch / MMRL、SELinux、Root 服务时序、OTA/补丁更新和真实 bootloop 场景测试；详见 `TESTING.md`。
