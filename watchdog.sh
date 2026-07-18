#!/system/bin/sh
# RescueX v3.2.0 - watchdog.sh
# 独立看门狗进程，由 post-fs-data.sh 启动
#
# v3.0.1 改进：
# - 看门狗超时触发三级渐进式救砖（而非之前的全量救砖）

# 推断 MODDIR
MODDIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
[ -z "$MODDIR" ] && MODDIR="${0%/*}"

# source 共享库
if [ ! -f "$MODDIR/common.sh" ]; then
    echo "[RescueX watchdog] common.sh not found, abort" >&2
    exit 1
fi
. "$MODDIR/common.sh"

# 超时参数
TIMEOUT="${1:-90}"
case "$TIMEOUT" in ''|*[!0-9]*) TIMEOUT=90 ;; esac

# 读取配置，取得可配置的轮询间隔
read_config

# v2.5 自适应轮询间隔
POLL_INTERVAL="$WATCHDOG_POLL_INTERVAL_SEC"
if [ "$TIMEOUT" -ge 600 ] && [ "$POLL_INTERVAL" -lt 5 ]; then
    POLL_INTERVAL=8
    log "[WD] 超时 ${TIMEOUT}s 较长，自动调整轮询间隔为 ${POLL_INTERVAL}s（原 ${WATCHDOG_POLL_INTERVAL_SEC}s）"
elif [ "$TIMEOUT" -ge 300 ] && [ "$POLL_INTERVAL" -lt 3 ]; then
    POLL_INTERVAL=5
    log "[WD] 超时 ${TIMEOUT}s 较长，自动调整轮询间隔为 ${POLL_INTERVAL}s（原 ${WATCHDOG_POLL_INTERVAL_SEC}s）"
fi

# 写入自己的 PID（供 service.sh 安全停止）
echo $$ > "$WATCHDOG_PID_FILE"

# v2.7.0 Q-007: trap 信号清理
# 被外部 kill 时（SIGTERM/SIGINT）清理 PID 文件，避免残留
cleanup_watchdog() {
    local current_pid
    current_pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
    [ "$current_pid" = "$$" ] && rm -f "$WATCHDOG_PID_FILE" 2>/dev/null
    log "[WD] 看门狗退出 (信号清理)"
    exit 0
}

cleanup_watchdog_pid_file() {
    local current_pid
    current_pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
    [ "$current_pid" = "$$" ] && rm -f "$WATCHDOG_PID_FILE" 2>/dev/null
}

# 注册信号处理
trap cleanup_watchdog TERM INT
trap cleanup_watchdog_pid_file EXIT

log "[WD] 看门狗启动 (PID=$$, timeout=${TIMEOUT}s, 轮询间隔=${POLL_INTERVAL}s)"

# 轮询检查
elapsed=0

while [ "$elapsed" -lt "$TIMEOUT" ]; do
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))

    # 条件 1: BOOT_END 已写入（service.sh 完整执行）
    boot_end=0
    if [ -f "$STATUS_FILE" ]; then
        boot_end=$(grep "^BOOT_END=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
        case "$boot_end" in ''|*[!0-9]*) boot_end=0 ;; esac
    fi
    if [ "$boot_end" != "0" ]; then
        log "[WD] 检测到 BOOT_END=$boot_end，启动完成，看门狗正常退出"
        cleanup_watchdog_pid_file
        exit 0
    fi

    # 条件 2: sys.boot_completed=1 且 SERVICE_STARTED=1（双条件）
    boot_completed=$(getprop sys.boot_completed 2>/dev/null)
    if [ "$boot_completed" != "1" ]; then
        boot_completed=$(getprop dev.bootcomplete 2>/dev/null)
        [ "$boot_completed" != "1" ] && boot_completed=$(getprop service.bootcomplete 2>/dev/null)
    fi

    if [ "$boot_completed" = "1" ]; then
        service_started=0
        if [ -f "$STATUS_FILE" ]; then
            service_started=$(grep "^SERVICE_STARTED=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
            case "$service_started" in ''|*[!0-9]*) service_started=0 ;; esac
        fi
        if [ "$service_started" = "1" ]; then
            log "[WD] sys.boot_completed=1 且 SERVICE_STARTED=1，启动完成，看门狗正常退出"
            cleanup_watchdog_pid_file
            exit 0
        fi
    fi
done

# 超时，检查是否 RESCUED 状态（避免重复触发）
if [ -f "$STATUS_FILE" ]; then
    last_result=$(grep "^LAST_BOOT_RESULT=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    if [ "$last_result" = "RESCUED" ]; then
        log "[WD] 状态已是 RESCUED，看门狗不重复触发，退出"
        cleanup_watchdog_pid_file
        exit 0
    fi
fi

# 触发救砖
log "[WD] 看门狗超时 ${TIMEOUT}s，boot 未完成，触发救砖"
watchdog_trigger

# watchdog_trigger 应该已重启系统，此处兜底
exit 0
