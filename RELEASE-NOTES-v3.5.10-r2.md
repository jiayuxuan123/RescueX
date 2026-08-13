# RescueX v3.5.10-r2

> 同级修复版：启动统计按 boot token 终态重构（治本），修复"救砖后成功率仍 100%"、
> "最近救砖显示从未"两大问题。版本 v3.5.10-r2 / versionCode 350202。

## 修复 1：成功率不再永远 100%（救砖/失败计入分母）

**根因**：post-fs-data 触发救砖时直接 `commit_verified_rescue` 后退出，
**从不写 START 历史行**；旧统计的 TOTAL 只数 START 行，因此救砖启动根本不进入
分母，成功率恒定 100%。此前"SUCCESS 钳制到 TOTAL"只是掩盖了虚高，救砖后
TOTAL 不变、SUCCESS 不变，仍显示 100%。

**修复**：`compute_boot_stats` 重写为**按 boot token 终态聚合**（awk）：

- `START`/`RESCUE`/`FAILURE` 行都会创建/记录 boot token（启动证据）；
  **postfs 救砖（仅 RESCUE 行）也计为一次启动（失败终态）**；
- `SERVICE` 行仅将已存在 token 升级为 SUCCESS（孤儿 SERVICE 行不计入）；
- 终态优先级：RESCUE > FAILURE > SUCCESS > PENDING（未完成）；
- 同一 token 多行只保留最高终态（重复行去重）。

效果：救砖/失败/未完成启动都会拉低成功率；`SUCCESS ≤ TOTAL` 数学必然成立。

## 修复 2：最近救砖不再显示"从未"

**根因链**：
1. 早期启动 RTC 未同步时 `commit_verified_rescue` 的 `get_valid_epoch()` 返回 0，
   写入 `LAST_RESCUE_TIME=0`；
2. `fix_last_rescue_time()` 有 `[ "$lrt" -eq 0 ] && return`，**跳过 0**，永不修正；
3. post-fs-data 先 `read_previous_status` 再 `fix_last_rescue_time`，
   随后 `write_status` 又用旧的 `PREV_LAST_RESCUE_TIME`（0）覆盖修正结果；
4. 统计层"历史优先"——历史 RESCUE 行时间为 `uptime+Ns`（非 epoch）时被丢弃，
   又错误地忽略状态文件时间。

**修复**：
- `fix_last_rescue_time`：`LAST_RESCUE_TIME=0` 且 `RESCUE_COUNT>0` 时，
  修正为当前时间（近似"最近救砖"），不再跳过 0；
- `post-fs-data.sh`：`fix_last_rescue_time` 移到 `read_previous_status` **之前**，
  修正结果不再被旧值覆盖；
- `commit_verified_rescue`：早期 RTC 时保留旧 `LAST_RESCUE_TIME`，避免 0 覆盖有效值；
- 统计层：历史无有效救砖时间时**回退状态文件时间**；救砖次数用
  `max(历史, status RESCUE_COUNT)` 做下限补偿（历史行被截断/写入失败时仍正确）。

## 离线验证（7 场景全通过）

| 场景 | 结果 |
|---|---|
| 正常 4 次全成功 | 4/4 = 100% |
| 脏数据 3 条孤儿 SERVICE | 孤儿不计，4/4 = 100% |
| **3 次救砖（无 START 行）** | **total=7 success=4 rate=57% rescued=3** |
| 混合 2 成功+1 失败+1 救砖+1 未完成 | 2/5 = 40% |
| 重复 SERVICE/RESCUE 行 | 去重，计数正确 |
| 早期 RTC（uptime 时间） | 时间回退状态文件 |
| 历史截断 + status 救砖 5 | rescued=5 下限补偿 |

`fix_last_rescue_time` 三场景：0+已救砖→修正为当前时间；0+未救砖→保持 0；
有效时间→不动。

## 版本号

v3.5.10-r2 / versionCode 350202（沿用 -rN 规则：主版本 35020 后追加两位递增）。

## 继承

v3.5.10 / v3.5.10-r1 全部功能（音量键 WebUI 选择、无 WebUI 模式、
配对计数基础）与 v3.5.9-r1/r2 全部修复均保留。
