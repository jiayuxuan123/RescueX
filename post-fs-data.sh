#!/system/bin/sh
# RescueX v3.2.2 - post-fs-data.sh
# 在系统启动早期执行，负责救砖逻辑核心
#
# v3.0.1 改进（专业级升级）：
# - 三级渐进式救砖：嫌疑禁用→全量+脚本锁定→APP解冻
# - 嫌疑模块精准追踪（基于 last-good 列表对比）
# - 脚本目录自动锁定（全量救砖时同时禁用 service.d 等）
# - APP 自动解冻（删除 package-restrictions.xml）

MODDIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
[ -z "$MODDIR" ] && MODDIR="${0%/*}"

if [ ! -f "$MODDIR/common.sh" ]; then
    exit 0
fi
. "$MODDIR/common.sh"

# ============================================================
# 仅 post-fs-data 使用的本地函数
# ============================================================

# 启动看门狗（双 fork 脱离父进程，watchdog.sh 自行写 PID）
start_watchdog() {
    local timeout="$1"

    # 双 fork 让看门狗脱离父进程（init 切换阶段不被清理）
    ( sh "$WATCHDOG_SCRIPT" "$timeout" >/dev/null 2>&1 < /dev/null & )

    # 等待 watchdog.sh 写入 PID
    local i=0
    while [ $i -lt 3 ]; do
        sleep 1
        if [ -f "$WATCHDOG_PID_FILE" ]; then
            local wd_pid
            wd_pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
            case "$wd_pid" in
                ''|*[!0-9]*) wd_pid=0 ;;
            esac
            if [ "$wd_pid" != "0" ] && kill -0 "$wd_pid" 2>/dev/null; then
                log "看门狗已启动 (PID=$wd_pid, timeout=${timeout}s)"
                return 0
            fi
        fi
        i=$((i + 1))
    done

    log "警告：看门狗启动后未找到存活进程，可能已被 init 清理"
    rm -f "$WATCHDOG_PID_FILE"
}

is_magisk_family() {
    [ -d "/data/adb/magisk" ] && return 0
    [ -f "/data/adb/magisk/util_functions.sh" ] && return 0
    return 1
}

handle_single_modules_update_stage() {
    local update_dir="$1"
    local backup_dir="$2"
    [ -d "$update_dir" ] || return 0

    log "检测到更新缓存目录: $update_dir，先转存为 $backup_dir"
    [ -d "$backup_dir" ] && rm -rf "$backup_dir" 2>/dev/null
    if mv -f "$update_dir" "$backup_dir" 2>/dev/null; then
        sync
        log "更新缓存转存完成: $backup_dir"
        return 0
    fi

    log "警告：更新缓存转存失败: $update_dir"
    return 1
}

handle_modules_update_stage() {
    handle_single_modules_update_stage "/data/adb/modules_update" "/data/adb/modules_update.bak"
    handle_single_modules_update_stage "/data/adb/modules_update_mmrl" "/data/adb/modules_update_mmrl.bak"
    return 0
}

replay_single_modules_update_backup() {
    local backup_dir="$1"
    local update_base="${MODULE_BASE:-/data/adb/modules}"
    local mod_dir mod_id moved=0

    [ -d "$backup_dir" ] || return 0

    log "检测到更新缓存备份: $backup_dir，开始回放待更新模块"
    mkdir -p "$update_base" 2>/dev/null

    for mod_dir in "$backup_dir"/*/; do
        [ ! -d "$mod_dir" ] && continue
        mod_id=$(basename "$mod_dir")
        case "$mod_id" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
        [ -d "$update_base/$mod_id" ] && rm -rf "$update_base/$mod_id" 2>/dev/null
        if mv -f "$mod_dir" "$update_base/" 2>/dev/null; then
            moved=$((moved + 1))
            log "已回放更新模块: $mod_id"
        else
            log "警告：回放更新模块失败: $mod_id"
        fi
    done

    rm -rf "$backup_dir" 2>/dev/null
    if [ "$moved" -gt 0 ]; then
        sync
        log "已从 $backup_dir 回放 $moved 个更新模块，立即重启进入下一轮启动验证"
        reboot
        exit 0
    fi
    return 0
}

replay_modules_update_backup() {
    replay_single_modules_update_backup "/data/adb/modules_update.bak"
    replay_single_modules_update_backup "/data/adb/modules_update_mmrl.bak"
    return 0
}

# ============================================================
# 主流程
# ============================================================

mkdir -p "$STATE_DIR"

# v2.7.2: 局部授权——仅对模块自身持久目录，不影响 /data 下其他文件
mkdir -p "$PERSIST_DIR" 2>/dev/null
chmod 770 "$PERSIST_DIR" 2>/dev/null
chown root:root "$PERSIST_DIR" 2>/dev/null || true

# v2.7.2: 应用用户自定义目录权限
if [ -f "$STATE_DIR/custom_dirs.conf" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        dir=$(echo "$line" | awk '{print $1}')
        perm=$(echo "$line" | awk '{print $2}')
        [ -z "$dir" ] || [ -z "$perm" ] && continue
        case "$perm" in 700|750|755|770) ;; *) continue ;; esac
        if ! is_safe_custom_dir "$dir"; then
            log "跳过不安全的自定义目录: $dir"
            continue
        fi
        mkdir -p "$dir" 2>/dev/null
        chmod "$perm" "$dir" 2>/dev/null
        chown root:root "$dir" 2>/dev/null || true
    done < "$STATE_DIR/custom_dirs.conf"
fi

# v2.7.0: 从持久目录恢复数据（模块更新后自动恢复）
restore_from_persist

read_config
read_previous_status   # 提前读取，供禁用分支使用

if is_magisk_family; then
    handle_modules_update_stage
    replay_modules_update_backup
fi

# v2.7.2: 提前修正异常 LAST_RESCUE_TIME（post-fs-data 阶段时钟可能已恢复）
# 与 service.sh 形成双保险，任一环节成功即可消除 "20261 天前" 的显示异常
fix_last_rescue_time

# 如果模块被禁用，跳过所有逻辑
if [ "$ENABLED" != "true" ]; then
    log "模块已禁用，跳过救砖逻辑"
    stop_watchdog
    write_status "MODULE_DISABLED" 0 "false" 0 "$PREV_RESCUE_COUNT" "$PREV_LAST_RESCUE_TIME"
    exit 0
fi

log "===== RescueX $RX_VERSION post-fs-data 启动 ====="
log "配置: 阈值=$REBOOT_THRESHOLD 超时=$BOOT_TIMEOUT_SEC OTA超时=$OTA_TIMEOUT_SEC 渐进=$PROGRESSIVE_RESCUE dry=$DRY_RUN 宽限=$USER_REBOOT_GRACE_SEC"

RISK_HITS=$(scan_and_block_destructive_scripts 2>/dev/null)
case "$RISK_HITS" in ''|*[!0-9]*) RISK_HITS=0 ;; esac
[ "$RISK_HITS" -gt 0 ] && log "已拦截 $RISK_HITS 个高风险脚本入口"

# v2.5 新增：启动模式检测
# Recovery / Fastbootd / Charger 等非正常启动模式不应被计入失败
NON_NORMAL_BOOT=0
if ! detect_boot_mode; then
    NON_NORMAL_BOOT=1
    log "检测到非正常启动模式（Recovery/Fastboot/Charger 等），跳过失败计数"
fi

# 清理上次残留的看门狗（模块启用路径）
stop_watchdog

# v2.7.0 LOG-003 修复：非正常启动模式跳过看门狗启动
# Recovery/Fastboot/Charger 等模式下不需要看门狗守护，
# 避免在 Recovery 刷机期间看门狗超时误触发救砖
if [ "$NON_NORMAL_BOOT" = "1" ]; then
    log "非正常启动模式，跳过看门狗和失败计数，直接退出"
    write_status "NON_NORMAL" "$PREV_FAIL_COUNT" "false" 0 "$PREV_RESCUE_COUNT" "$PREV_LAST_RESCUE_TIME"
    exit 0
fi

# 读取白名单
read_whitelist

log "上次状态: result=$PREV_BOOT_RESULT fail=$PREV_FAIL_COUNT service_started=$PREV_SERVICE_STARTED"

# 判断上次是否真的启动失败
# v2.5：非正常启动模式下跳过失败计数（避免 Recovery 刷机后被误判）
if [ "$NON_NORMAL_BOOT" = "1" ]; then
    log "非正常启动模式，跳过失败计数判定"
elif is_real_boot_failure; then
    PREV_FAIL_COUNT=$((PREV_FAIL_COUNT + 1))
    log "检测到上次启动失败，失败次数: $PREV_FAIL_COUNT / $REBOOT_THRESHOLD"
else
    # 上次成功或用户主动重启
    # v3.0.1 BUG FIX: 用 BOOT_END 判定替代 SERVICE_STARTED
    # 原逻辑 SERVICE_STARTED=1 就重置失败计数，但 service.sh 可能只执行了
    # mark_service_started() 就被中断（如测试模块触发重启），实际启动并未完成
    # 正确判定：BOOT_END 非零 或 LAST_BOOT_RESULT=SUCCESS 才算真正启动成功
    if [ "$PREV_BOOT_RESULT" = "SUCCESS" ] || [ "$PREV_BOOT_END" != "0" ]; then
        PREV_FAIL_COUNT=0
        log "上次启动成功，失败计数已重置"
    fi
fi

# 检测 OTA 状态（底层固件刷机）
TIMEOUT_TO_USE="$BOOT_TIMEOUT_SEC"
OTA_DETECTED="false"
PATCH_DETECTED="false"
if detect_ota; then
    OTA_DETECTED="true"
    TIMEOUT_TO_USE="$OTA_TIMEOUT_SEC"
    log "检测到底层 OTA 升级，超时延长至 ${OTA_TIMEOUT_SEC} 秒"
fi

# v2.4 新增：检测补丁更新（上层系统更新，与 OTA 隔离）
if [ "$OTA_DETECTED" != "true" ] && detect_patch_update; then
    PATCH_DETECTED="true"
    TIMEOUT_TO_USE="$PATCH_UPDATE_TIMEOUT_SEC"
    log "检测到补丁更新（ColorOS/MIUI 等），超时设为 ${PATCH_UPDATE_TIMEOUT_SEC} 秒"
fi

# v2.7.0 LOG-001 修复：补丁窗口期隔离普通失败计数
# 原问题：处于补丁更新窗口期时，如果启动失败，普通 FAIL_COUNT 也会被递增，
# 导致补丁失败同时触发普通救砖流程，与补丁回滚设计意图冲突。
# 修复：补丁窗口期内，仅递增补丁失败计数，不动普通 FAIL_COUNT
read_patch_fail_count
trigger_rescue_flag=0
if [ "$PATCH_DETECTED" = "true" ] || [ -f "$PATCH_FLAG_FILE" ]; then
    # 处于补丁更新窗口期，检查上次是否补丁启动失败
    if is_real_boot_failure; then
        # 这是补丁更新后的失败，增加补丁失败计数（不动普通 FAIL_COUNT）
        if [ "$PREV_BOOT_RESULT" != "RESCUED" ] && [ "$PREV_SERVICE_STARTED" != "1" ]; then
            PATCH_FAIL_COUNT=$((PATCH_FAIL_COUNT + 1))
            write_patch_fail_count "$PATCH_FAIL_COUNT"
            log "补丁更新失败计数: $PATCH_FAIL_COUNT / $PATCH_FAIL_THRESHOLD"

            # 达到补丁失败阈值，触发轻量级回滚（不清整机数据）
            if [ "$PATCH_FAIL_COUNT" -ge "$PATCH_FAIL_THRESHOLD" ] && [ "$PATCH_AUTO_ROLLBACK" = "true" ]; then
                log "补丁失败次数达阈值，触发补丁回滚（保留用户数据）"
                patch_rollback
                write_patch_fail_count 0
                # v2.7.0: 补丁回滚后不重置 PREV_FAIL_COUNT 为 0，
                # 而是保持原值，避免掩盖普通启动失败
            fi
        fi
    fi
    # v2.7.0 LOG-001 核心修复：补丁窗口期内，跳过普通救砖流程
    # 避免补丁失败和普通失败双重递增
    log "补丁更新窗口期，跳过普通失败计数和救砖判定"
else
    # 非补丁窗口期：正常的失败计数和救砖判定
    # v3.0.1: 统一使用 three_level_rescue，确保嫌疑禁用失败时有兜底
    trigger_rescue_flag=0
    if [ "$PREV_FAIL_COUNT" -ge "$REBOOT_THRESHOLD" ]; then
        log "连续启动失败 $PREV_FAIL_COUNT 次 >= 阈值 $REBOOT_THRESHOLD，触发三级救砖"
        three_level_rescue
        trigger_rescue_flag=1
    elif [ "$PROGRESSIVE_RESCUE" = "true" ] && [ "$PREV_FAIL_COUNT" -ge 1 ]; then
        log "渐进式救砖触发 (失败 $PREV_FAIL_COUNT 次)"
        # v3.0.1 FIX: 使用 three_level_rescue 替代直接调用 suspect_rescue
        # 原逻辑 PREV_FAIL_COUNT=1 时直接调用 suspect_rescue，
        # 但 suspect_rescue 失败后没有兜底，导致嫌疑模块仅被标记而未禁用
        # three_level_rescue 内部会根据 RESCUE_LEVEL 选择策略，
        # 且 Level 0 失败后会立即升级到 Level 1（全量救砖）
        three_level_rescue
        trigger_rescue_flag=1
    fi

    # 更新救砖计数
    if [ "$trigger_rescue_flag" = "1" ]; then
        PREV_RESCUE_COUNT=$((PREV_RESCUE_COUNT + 1))
        PREV_LAST_RESCUE_TIME=$(date +%s)
    fi

    # AUTO_REENABLE: 救砖后下次启动自动恢复
    if [ "$AUTO_REENABLE" = "true" ] && [ "$PREV_BOOT_RESULT" = "RESCUED" ]; then
        log "AUTO_REENABLE 启用，自动恢复被救砖禁用的模块"
        reenable_all
        PREV_FAIL_COUNT=0
    fi
fi

# 记录本次启动开始
CURRENT_UPTIME=$(get_uptime_sec)
CURRENT_BOOT_START=$(date +%s)
write_status "BOOTING" "$PREV_FAIL_COUNT" "$OTA_DETECTED" 0 "$PREV_RESCUE_COUNT" "$PREV_LAST_RESCUE_TIME" "$CURRENT_BOOT_START" "$CURRENT_UPTIME" "$PATCH_DETECTED"

# v2.7.2: 救砖发生后立即持久化累计值，防止升级/覆盖丢失
if [ "$trigger_rescue_flag" = "1" ]; then
    sync_to_persist
fi

log "本次启动 uptime 起点: ${CURRENT_UPTIME}s (boot_start=$CURRENT_BOOT_START, ota=$OTA_DETECTED, patch=$PATCH_DETECTED)"

# 启动看门狗
start_watchdog "$TIMEOUT_TO_USE"

log "RescueX 初始化完成，等待系统完成启动..."
