# RescueX - 自动救砖守护

Android 自动救砖模块，兼容 Magisk / KernelSU / APatch。

模块启动后监控开机状态：连续重启达到阈值、开机超时未完成时，自动禁用问题模块并恢复系统。

## 功能

- **连续重启救砖**：达到阈值（默认 3 次）自动禁用所有非白名单模块
- **开机超时看门狗**：开机超过指定时长未完成，自动救砖并重启
- **三级渐进式救砖**：嫌疑模块禁用 → 全量禁用 + 脚本锁定 → APP 解冻
- **OTA / 补丁更新识别**：区分底层 OTA 和系统补丁，自动调整超时策略
- **嫌疑模块追踪**：启动成功后记录已知良好模块列表，下次失败时对比差异精确定位
- **模块快照管理**：手动拍快照记录当前模块启用状态，出问题可一键回滚
- **稳定基线恢复**：一键恢复上次成功启动时的已知良好模块状态
- **自定义目录权限**：启动时自动对指定目录设置安全权限
- **WebUI 管理面板**：在 KernelSU 管理器 / Magisk v27+ / MMRL 中直接管理所有功能
- **轻量完整性自检**：启动成功后建立 RescueX 核心文件 SHA-256 基线，独立守护进程按随机间隔检查并在 WebUI 展示结果

## 安装

在 Magisk / KernelSU / APatch 管理器中刷入 [Releases](https://github.com/jiayuxuan123/RescueX/releases) 页面下载的 zip 包并重启即可。

## 开源仓库

- 仓库地址：https://github.com/jiayuxuan123/RescueX
- 在线更新：模块已内置 `updateJson`，发布新版 Release 后可直接从管理器检查更新

### 兼容性

| Root 方案      | 状态   |
|---------------|--------|
| Magisk v27+   | 完全兼容 |
| KernelSU      | 完全兼容 |
| SukiSU Ultra  | 完全兼容 |
| APatch        | 完全兼容 |
| MMRL v34242+ | 兼容 |

说明：MMRL 的旧版本存在模块操作按钮相关的 Compose 崩溃。RescueX 已避免在 MMRL 前台通过 `action.sh` 二次拉起自身 WebUI，建议使用 `v34242+`。

## 使用

### 通过 WebUI（推荐）

在 KernelSU 管理器 / Magisk v27+ 中打开 RescueX 模块页面，或通过 MMRL / KsuWebUI 打开 WebUI，即可进行所有配置和管理操作。

如果当前前台已经是 MMRL，`action.sh` 会跳过再次拉起 MMRL 自己的 `WebUIActivity`，避免在部分机型上触发前台重入崩溃。

### 通过命令行

```bash
# 查看模块状态
sh /data/adb/modules/RescueX/action.sh
```

### 配置参数

| 参数           | 默认值  | 范围     | 说明                    |
|---------------|---------|---------|------------------------|
| 连续重启阈值     | 3 次    | 1-10    | 达到此次数后触发全量救砖    |
| 开机超时        | 90 秒   | 30-600  | 超时未完成开机则判定失败    |
| OTA 升级超时    | 900 秒  | 60-1800 | 检测到 OTA 时使用此超时    |
| 用户重启宽限期   | 30 秒   | 5-300   | 短时间内重启不计入失败次数  |
| 补丁更新超时     | 180 秒  | 60-600  | 补丁更新时的超时时间        |
| 补丁失败阈值     | 2 次    | 1-5     | 达到此次数后回滚补丁        |
| 轻量完整性自检   | 开启    | 开启/关闭 | 检查 RescueX 核心文件是否缺失或被替换 |

## 工作流程

2. `watchdog.sh` — 后台监控超时，超时后触发三级渐进式救砖
3. `service.sh` — 系统完全启动后执行，标记启动成功、保存已知良好模块、更新状态
4. `integrity.sh` — 启动成功后独立运行，按随机间隔校验 RescueX 核心文件并写入完整性状态

## 许可证

[MIT](LICENSE)

## 感谢

- [Magisk](https://github.com/topjohnwu/Magisk)
- [KernelSU](https://github.com/tiann/KernelSU)
- [APatch](https://github.com/bmax121/APatch)
- [MMRL](https://github.com/DerGoogler/MMRL)


## v3.4.0 安全测试说明

> **这是灰度测试包，不是稳定版。首次安装默认 `DRY_RUN=true`：只记录拟执行的救援动作，不改动模块状态。**

本版针对审计风险做了安全收敛：

- 恢复清单缺失、为空或格式异常时，**拒绝恢复**，不会恢复全部禁用模块；
- 自动 Level 2 已禁用：不会删除 `package-restrictions.xml`；
- 自动救援使用跨进程目录锁和 `rescue.plan`/`rescue.commit` 事务记录；
- 补丁窗口带 TTL；无可信补丁快照时不自动猜测性回滚；
- 看门狗采用多信号健康确认；自动路径只请求一次普通重启，不进入 Recovery、不使用 SysRq；
- 完整性基线版本不匹配时只告警，不自动重建。

### 首次真机测试顺序

1. 只在备用设备进行，先完整备份 boot/vendor、模块目录和重要数据。
2. 安装 ZIP 后确认 WebUI 可打开、状态目录可读、日志可生成。
3. 保持 `DRY_RUN=true`，验证正常启动 3 次与手动重启 1 次都不误触发救援。
4. 检查 `rescue.log`、`rescue_audit.log`、`rescue.plan`/`rescue.commit`；确认不会出现 Recovery/SysRq 路径。
5. 在可随时救援的环境中逐项测试模块禁用、快照、补丁标记 TTL 和看门狗健康信号。
6. 只有完成测试清单且明确把 `DRY_RUN=false` 后，才可测试真实模块状态修改。

详细项目测试项见 `TESTING.md`。
