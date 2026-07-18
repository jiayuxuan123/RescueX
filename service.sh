#!/system/bin/sh
# RescueX v3.2.6 - service.sh
# 系统完全启动后执行，标记启动成功
#
# v3.0.1 改进：
# - 启动成功后保存已知良好模块列表（嫌疑追踪核心）
# - 三级救砖级别重置（成功后回到级别 0）

MODDIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
[ -z "$MODDIR" ] && MODDIR="${0%/*}"

if [ ! -f "$MODDIR/common.sh" ]; then
    exit 0
fi
. "$MODDIR/common.sh"

# ============================================================
# 仅 service.sh 使用的本地函数
# ============================================================

# 立即标记 service.sh 已执行（兜底）
mark_service_started() {
    if [ ! -f "$STATUS_FILE" ]; then
        local now up
        now=$(date +%s)
        up=$(get_uptime_sec)
        write_status "BOOTING" 0 "false" 1 0 0 "$now" "$up"
        return
    fi

    local boot_start=0 fail_count=0 ota_detected=false rescue_count=0 last_rescue_time=0 uptime_start=0 patch_detected=false
    local k v
    while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        case "$k" in
            BOOT_START) boot_start="$v" ;;
            FAIL_COUNT) fail_count="$v" ;;
            OTA_DETECTED) ota_detected="$v" ;;
            RESCUE_COUNT) rescue_count="$v" ;;
            LAST_RESCUE_TIME) last_rescue_time="$v" ;;
            UPTIME_START) uptime_start="$v" ;;
            PATCH_DETECTED) patch_detected="$v" ;;
        esac
    done < "$STATUS_FILE"

    case "$boot_start" in ''|*[!0-9]*) boot_start=0 ;; esac
    case "$fail_count" in ''|*[!0-9]*) fail_count=0 ;; esac
    case "$rescue_count" in ''|*[!0-9]*) rescue_count=0 ;; esac
    case "$last_rescue_time" in ''|*[!0-9]*) last_rescue_time=0 ;; esac
    case "$uptime_start" in ''|*[!0-9]*) uptime_start=0 ;; esac

    local tmp="${STATUS_TMP}.$$"
    cat > "$tmp" << STATUS
BOOT_START=$boot_start
BOOT_END=0
SERVICE_STARTED=1
FAIL_COUNT=$fail_count
LAST_BOOT_RESULT=BOOTING
OTA_DETECTED=$ota_detected
RESCUE_COUNT=$rescue_count
LAST_RESCUE_TIME=$last_rescue_time
BOOT_DURATION=0
UPTIME_START=$uptime_start
UPTIME_END=0
PATCH_DETECTED=$patch_detected
STATUS

    sync "$tmp" 2>/dev/null
    mv "$tmp" "$STATUS_FILE"
    # SEC-005: 运行时创建文件显式 chmod 0600
    chmod 0600 "$STATUS_FILE" 2>/dev/null
}

# 更新 module.prop description
update_module_prop() {
    local threshold timeout_val model new_desc rescue_count suspect_info level
    threshold="$REBOOT_THRESHOLD"
    timeout_val="$BOOT_TIMEOUT_SEC"
    case "$threshold" in ''|*[!0-9]*) threshold=3 ;; esac
    case "$timeout_val" in ''|*[!0-9]*) timeout_val=90 ;; esac

    model=$(getprop ro.product.model 2>/dev/null | tr -cd 'A-Za-z0-9 ._-')
    [ -z "$model" ] && model="Device"

    # 读取救砖次数
    rescue_count=0
    if [ -f "$STATUS_FILE" ]; then
        rescue_count=$(grep "^RESCUE_COUNT=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
        case "$rescue_count" in ''|*[!0-9]*) rescue_count=0 ;; esac
    fi

    # 读取嫌疑模块
    suspect_info=""
    if [ -f "$SUSPECT_LOG" ]; then
        local suspects
        suspects=$(grep -v '^?' "$SUSPECT_LOG" 2>/dev/null | grep -v '^#' | grep -v '^unknown$' | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
        if [ -n "$suspects" ]; then
            suspect_info=" 嫌疑:${suspects}"
        fi
    fi

    # 读取救砖级别
    if [ -f "$RESCUE_LEVEL_FILE" ]; then
        level=$(cat "$RESCUE_LEVEL_FILE" 2>/dev/null | tr -d ' \t\r\n')
    fi
    [ -z "$level" ] && level=0

    new_desc="[守护中] ${model} | 阈值:${threshold}次 | 超时:${timeout_val}s | 救砖:${rescue_count}次 | 级别:${level}${suspect_info}"

    if [ -f "$MODDIR/module.prop" ]; then
        # 先恢复备份（如果存在），防止多次更新积累冗余
        if [ -f "$MODDIR/module.prop.bak" ]; then
            cp -f "$MODDIR/module.prop.bak" "$MODDIR/module.prop" 2>/dev/null
        fi
        grep -v "^description=" "$MODDIR/module.prop" > "$MODDIR/module.prop.tmp" 2>/dev/null
        echo "description=$new_desc" >> "$MODDIR/module.prop.tmp"
        sync "$MODDIR/module.prop.tmp" 2>/dev/null
        mv "$MODDIR/module.prop.tmp" "$MODDIR/module.prop"
    fi
}

# ============================================================
# 主流程
# ============================================================

read_config

# 检测是否处于 RESCUED 状态
if [ -f "$STATUS_FILE" ]; then
    PREV_RESULT_CHECK=$(grep "^LAST_BOOT_RESULT=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    if [ "$PREV_RESULT_CHECK" = "RESCUED" ]; then
        log "===== RescueX $RX_VERSION service 启动（检测到 RESCUED 状态）====="
        fix_last_rescue_time
        exit 0
    fi
fi

# 1. 立即标记 SERVICE_STARTED=1（兜底）
mark_service_started
log "===== RescueX $RX_VERSION service 启动 ====="

# 2. 等待系统真正完成启动（带 300 秒超时）
WAIT_SEC=0
WAIT_MAX=300
FAST_POLL_SEC=15
_boot_done=0
until [ "$_boot_done" = "1" ]; do
    if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] \
        || [ "$(getprop dev.bootcomplete 2>/dev/null)" = "1" ] \
        || [ "$(getprop service.bootcomplete 2>/dev/null)" = "1" ]; then
        _boot_done=1
        break
    fi
    if [ "$WAIT_SEC" -lt "$FAST_POLL_SEC" ]; then
        sleep 1
        WAIT_SEC=$((WAIT_SEC + 1))
    else
        sleep 3
        WAIT_SEC=$((WAIT_SEC + 3))
    fi
    if [ "$WAIT_SEC" -ge "$WAIT_MAX" ]; then
        log "警告：等待 boot_completed 超时 ${WAIT_MAX}s，但仍标记为成功"
        break
    fi
done
unset _boot_done
sleep 3
log "系统启动完成（等待 ${WAIT_SEC}s + 3s）"

notify_pending_script_risk_alert >/dev/null 2>&1

# 3. 安全停止看门狗
stop_watchdog

# 4. 原子写入最终状态
BOOT_END=$(date +%s)
CURRENT_UPTIME=$(get_uptime_sec)

update_status_fields "$BOOT_END" 1 "SUCCESS" 0 "$CURRENT_UPTIME"

# 修正可能异常的 LAST_RESCUE_TIME（post-fs-data 阶段时钟未同步）
fix_last_rescue_time

# 从状态文件读取计算后的 boot_duration 用于日志
BOOT_DURATION=0
if [ -f "$STATUS_FILE" ]; then
    BOOT_DURATION=$(grep "^BOOT_DURATION=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    case "$BOOT_DURATION" in ''|*[!0-9]*) BOOT_DURATION=0 ;; esac
fi

if [ "$BOOT_DURATION" -gt 0 ]; then
    log "本次启动耗时: ${BOOT_DURATION} 秒 (uptime 法, 不依赖 RTC)"
else
    log "本次启动耗时: 未能计算 (uptime_start=0 或异常)"
fi
log "启动成功，失败计数已重置"

# 写入 SERVICE 历史记录
echo "[$(get_log_time)] SERVICE | duration=${BOOT_DURATION}s | result=SUCCESS" >> "$HISTORY_FILE"
_truncate_history

# 启动成功后清除补丁更新标记
if [ -f "$PATCH_FLAG_FILE" ]; then
    clear_patch_flag
elif [ -f "$PATCH_FAIL_COUNT_FILE" ]; then
    write_patch_fail_count 0
fi

# v3.0.1: 启动成功后保存已知良好模块列表
log "保存已知良好模块列表（用于嫌疑追踪）"
save_good_modules

# v2.7.0: 启动成功后同步持久数据
sync_to_persist

# 6. 更新 module.prop description
update_module_prop

log "RescueX $RX_VERSION service.sh 完成"
