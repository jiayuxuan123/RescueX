#!/system/bin/sh
# RescueX v3.4.0 - service.sh
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

service_boot_token=""

capture_service_boot_token() {
    service_boot_token=$(grep '^BOOT_TOKEN=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    [ -n "$service_boot_token" ] || service_boot_token=$(get_boot_token)
}

service_status_owned() {
    local current_result current_token
    current_result=$(grep '^LAST_BOOT_RESULT=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    current_token=$(grep '^BOOT_TOKEN=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    if [ "$current_result" != BOOTING ]; then
        log "拒绝提交成功：状态已被外部流程改为 ${current_result:-UNKNOWN}"
        return 1
    fi
    if [ -n "$current_token" ] && [ "$current_token" != "$service_boot_token" ]; then
        log "拒绝提交成功：状态 token 已变化（旧=$service_boot_token 新=$current_token）"
        return 1
    fi
    return 0
}

# 立即标记 service.sh 已执行（兜底）
mark_service_started() {
    if [ ! -f "$STATUS_FILE" ]; then
        local now up
        now=$(get_valid_epoch)
        up=$(get_uptime_sec)
        write_status "BOOTING" 0 "false" 1 0 0 "$now" "$up"
        return
    fi

    local boot_start=0 boot_token="" fail_count=0 ota_detected=false rescue_count=0 last_rescue_time=0 uptime_start=0 patch_detected=false prior_result="UNKNOWN"
    local k v
    while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        case "$k" in
            BOOT_START) boot_start="$v" ;;
            BOOT_TOKEN) boot_token="$v" ;;
            LAST_BOOT_RESULT) prior_result="$v" ;;
            FAIL_COUNT) fail_count="$v" ;;
            OTA_DETECTED) ota_detected="$v" ;;
            RESCUE_COUNT) rescue_count="$v" ;;
            LAST_RESCUE_TIME) last_rescue_time="$v" ;;
            UPTIME_START) uptime_start="$v" ;;
            PATCH_DETECTED) patch_detected="$v" ;;
        esac
    done < "$STATUS_FILE"

    case "$boot_start" in ''|*[!0-9]*) boot_start=0 ;; esac
    [ "$prior_result" = FAILURE ] || [ "$prior_result" = TEST_FAILURE ] || [ "$prior_result" = RESCUED ] && {
        log "service 检测到终态 $prior_result，拒绝覆盖并跳过成功等待"
        sync_to_persist
        return 1
    }
    if [ -n "$boot_token" ] && [ "$boot_token" != "$(get_boot_token)" ]; then
        log "service 拒绝覆盖其他内核启动事务（BOOT_TOKEN=$boot_token）"
        return 0
    fi
    [ -n "$boot_token" ] || boot_token=$(get_boot_token)
    case "$fail_count" in ''|*[!0-9]*) fail_count=0 ;; esac
    case "$rescue_count" in ''|*[!0-9]*) rescue_count=0 ;; esac
    case "$last_rescue_time" in ''|*[!0-9]*) last_rescue_time=0 ;; esac
    case "$uptime_start" in ''|*[!0-9]*) uptime_start=0 ;; esac

    local tmp="${STATUS_TMP}.$$"
    cat > "$tmp" << STATUS
BOOT_START=$boot_start
BOOT_TOKEN=${boot_token:-$(get_boot_token)}
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
        suspects=$(grep -v '^?' "$SUSPECT_LOG" 2>/dev/null | grep -v '^+' | grep -v '^#' | grep -v '^unknown$' | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
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
        # module.prop is runtime metadata. Rewrite only its description through
        # a temp file; never restore a stale backup that could roll back the
        # installed versionCode after an overlay update.
        local prop_tmp="$MODDIR/module.prop.tmp.$$"
        if grep -v "^description=" "$MODDIR/module.prop" > "$prop_tmp" 2>/dev/null && \
            echo "description=$new_desc" >> "$prop_tmp" && \
            sync "$prop_tmp" 2>/dev/null && mv "$prop_tmp" "$MODDIR/module.prop"; then
            chmod 0644 "$MODDIR/module.prop" 2>/dev/null
        else
            rm -f "$prop_tmp" 2>/dev/null
            log "警告：module.prop 更新失败，保留当前元数据"
        fi
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

# 1. 立即标记 SERVICE_STARTED=1（兜底）。若外部流程已提交 FAILURE/
# TEST_FAILURE/RESCUED，则不进入等待循环，更不能把终态改写为成功。
if ! mark_service_started; then
    log "===== RescueX $RX_VERSION service 跳过：已有终态 ====="
    exit 0
fi
capture_service_boot_token
log "===== RescueX $RX_VERSION service 启动 ====="
v35_health_touch service running "waiting_for_boot_completed"

# 2. 等待系统真正完成启动。必须与 post-fs-data 的实际看门狗窗口
# 保持一致：普通启动使用经上下限约束的历史自适应值，OTA/补丁使用
# 专用窗口；避免 service 在 300 秒先退出并制造遗留 BOOTING。
WAIT_SEC=0
WAIT_MAX="$(get_effective_boot_timeout)"
if grep -q '^OTA_DETECTED=true$' "$STATUS_FILE" 2>/dev/null; then
    WAIT_MAX="$OTA_TIMEOUT_SEC"
elif grep -q '^PATCH_DETECTED=true$' "$STATUS_FILE" 2>/dev/null; then
    WAIT_MAX="$PATCH_UPDATE_TIMEOUT_SEC"
fi
case "$WAIT_MAX" in ''|*[!0-9]*) WAIT_MAX=300 ;; esac
[ "$WAIT_MAX" -lt 60 ] 2>/dev/null && WAIT_MAX=60
[ "$WAIT_MAX" -gt 1800 ] 2>/dev/null && WAIT_MAX=1800
FAST_POLL_SEC=15
log "service 等待 boot_completed，窗口=${WAIT_MAX}s"
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
        log "警告：等待 boot_completed 超时 ${WAIT_MAX}s，保留 BOOTING 状态交给看门狗处理"
        break
    fi
done
if [ "$_boot_done" != "1" ]; then
    log "系统启动未确认完成，跳过成功收尾"
    v35_health_touch service error "boot_completed_timeout"
    v35_timeline_append BOOT_FAIL critical timeout "wait=${WAIT_MAX}s"
    exit 1
fi
unset _boot_done

sleep 3
log "系统启动完成（等待 ${WAIT_SEC}s + 3s）"


# 3. 只有仍持有本次启动事务且状态仍为 BOOTING，才允许提交 SUCCESS。
# TestTarget/看门狗/其他启动流程写入 FAILURE 或 RESCUED 后，不能被迟到的
# service 收尾覆盖，否则统计会出现“失败被记成成功”的假象。
if ! service_status_owned; then
    current_terminal=$(grep '^LAST_BOOT_RESULT=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    # A watchdog may already be committing RESCUED and scheduling reboot. Never
    # kill that watchdog or add a contradictory FAILURE event.
    if [ "$current_terminal" = "RESCUED" ]; then
        log "service 发现看门狗已提交 RESCUED，交由救砖重启路径完成"
        sync_to_persist
        v35_health_touch service warning "rescued_by_watchdog"
        exit 0
    fi
    stop_watchdog
    case "$current_terminal" in
        FAILURE|TEST_FAILURE)
            append_boot_history "[$(get_log_time)] FAILURE | boot=$service_boot_token | result=$current_terminal" || true
            ;;
        *)
            append_boot_history "[$(get_log_time)] STATE | boot=$service_boot_token | result=OWNERSHIP_LOST" || true
            ;;
    esac
    sync_to_persist
    v35_health_touch service error "status_ownership_lost"
    exit 0
fi
stop_watchdog

# 4. 原子写入最终状态
BOOT_END=$(get_valid_epoch)
CURRENT_UPTIME=$(get_uptime_sec)

update_status_fields "$BOOT_END" 1 "SUCCESS" 0 "$CURRENT_UPTIME" "$service_boot_token" || {
    log "启动成功提交被拒绝，保留当前状态"
    append_boot_history "[$(get_log_time)] FAILURE | boot=$service_boot_token | result=STATUS_COMMIT_REJECTED" || true
    sync_to_persist
    exit 0
}

# 修正可能异常的 LAST_RESCUE_TIME（post-fs-data 阶段时钟未同步）
fix_last_rescue_time

# A confirmed successful boot may restore only modules disabled by the one-shot
# safe-mode transaction. Rescue actions and third-party script permissions are untouched.
v35_restore_one_shot_safe_mode || log "警告：一次性安全模式精确恢复未完成"

# 从状态文件读取计算后的 boot_duration 用于日志
BOOT_DURATION=0
if [ -f "$STATUS_FILE" ]; then
    BOOT_DURATION=$(grep "^BOOT_DURATION=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    case "$BOOT_DURATION" in ''|*[!0-9]*) BOOT_DURATION=0 ;; esac
fi

if [ "$BOOT_DURATION" -gt 0 ]; then
    # 仅成功提交后的合理 uptime 耗时进入移动平均，避免故障/时钟异常污染。
    record_boot_duration "$BOOT_DURATION" || log "警告：启动耗时历史写入失败"
    log "本次启动耗时: ${BOOT_DURATION} 秒 (uptime 法, 不依赖 RTC)"
else
    log "本次启动耗时: 未能计算 (uptime_start=0 或异常)"
fi
log "启动成功，失败计数已重置"

# 写入 SERVICE 历史记录
append_boot_history "[$(get_log_time)] SERVICE | boot=$service_boot_token | duration=${BOOT_DURATION}s | result=SUCCESS" || log "警告：SERVICE 历史写入失败"

# 启动成功后清除补丁更新标记
if [ -f "$PATCH_FLAG_FILE" ]; then
    clear_patch_flag
elif [ -f "$PATCH_FAIL_COUNT_FILE" ]; then
    write_patch_fail_count 0
fi

# v3.0.1: 启动成功后保存已知良好模块列表
log "保存已知良好模块列表（用于嫌疑追踪）"
save_good_modules
v35_promote_module_inventory || log "警告：模块变更基线保存失败"
v35_timeline_append BOOT_SUCCESS success confirmed "duration=${BOOT_DURATION}s"
v35_health_touch service healthy "boot_success,duration=${BOOT_DURATION}s"
v35_health_touch postfs healthy "boot_confirmed"

# v2.7.0: 启动成功后同步持久数据
sync_to_persist

# 6. 更新 module.prop description
update_module_prop

# 所有启动成功收尾动作完成后拉起长期完整性自检守护
start_integrity_daemon
log "完整性自检守护已启动（开关=${INTEGRITY_CHECK_ENABLED}）"

log "RescueX $RX_VERSION service.sh 完成"
