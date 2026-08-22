# RescueX v3.5.10-r3

> 系统 OTA 检测与升级状态可靠性修复。版本 `v3.5.10-r3` / `versionCode 350203`。

## 核心修复：跨厂商系统 OTA / 大版本升级识别

此前检测主要依赖 `sys.ota.update_state`、Recovery/BCB、`/metadata/ota` 和
`update_engine` 临时状态。许多中国及海外 OEM 会替换、提前清理或完全不暴露这些
信号，导致系统 OTA 的首次启动仍使用普通超时。

本版新增独立的 `ota-detection.sh` 检测层：

- 安装时记录当前系统构建基线到 `/data/adb/rescuex_data/ota_build_baseline`；
- 开机早期将当前系统与上一次 **确认成功启动** 的基线比较：构建指纹、增量版本、
  安全补丁、API/Android 版本、构建 ID、system/vendor/product/bootimage 指纹和 A/B 槽位；
- 任一可信构建身份变化都会启用 `OTA_TIMEOUT_SEC`，不依赖特定厂商 OTA 客户端；
- 旧有属性、Recovery、BCB、`/metadata/ota`、`update_engine` 信号仍保留为兼容兜底；
- 基线只在 `service.sh` 已提交 `SUCCESS` 后前进。新系统未能启动时，旧基线不会被覆盖，
  后续重试仍会保留 OTA 长超时；
- WebUI 和 CLI 均显示检测来源。无法自动识别的 ROM 可设置一次性 OTA 手动保护，成功启动后自动清除。

这套逻辑只选择启动超时窗口和记录诊断状态；没有修改失败计数、模块禁用、救砖事务、
模块恢复、看门狗触发或重启逻辑。

## 可靠性修复

- 修复补丁标记已经改为结构化状态文件后，WebUI 仍按旧的纯 `1` 值判断，导致已设置标记
  显示错误且难以清除的问题；
- 修复 `features-v35.sh` 预建空目录导致覆盖更新后无法恢复持久化健康时间线、模块基线等
  v35 状态的问题；
- 修复自适应启动超时的 `boot_duration_history` 未写入持久化镜像，模块更新后学习历史丢失的问题；
- WebUI 配置读取失败时，恢复与安装器一致的 `DRY_RUN=true` 安全默认值；
- 修复 CLI 未向 `rescue restore --apply` 等命令转发第三个参数的问题，并增加
  `action.sh --cli ota status|arm --apply|clear --apply`。

## 验证

离线测试共 15 项通过：

- 无基线、相同构建、构建指纹/增量版本/安全补丁/A-B 槽位变更；
- 手动保护、旧信号兜底、损坏基线 fail-closed、SUCCESS 后才提交基线；
- WebUI/CLI 回归、完整性清单覆盖；
- v35 持久化恢复、当前状态保护、自适应启动耗时历史镜像与恢复。

同时通过 `sh -n` 全部 Shell 脚本和 `node --check webroot/script.js`。

## 实机验证清单

由于系统 OTA 行为依赖设备和 ROM，发布前仍建议至少验证：

1. 正常重启仍使用普通或自适应超时；
2. A/B OTA 后首次启动显示 `build_baseline` 或兼容信号并使用 OTA 超时；
3. 非 A/B / Recovery OTA 或厂商大版本更新后，构建身份变化能触发 OTA 超时；
4. 在 `DRY_RUN=true` 下模拟一次更新后失败，确认多次重启均不覆盖旧构建基线；
5. 无法自动识别的 ROM 设置 OTA 手动保护后，首次成功启动会自动清除标记；
6. 模块覆盖更新后，v35 时间线和自适应启动耗时历史仍然保留。
