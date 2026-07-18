#!/system/bin/sh
# RescueX v3.2.4 - common.sh
# 共享函数库，被 post-fs-data.sh / service.sh / watchdog.sh / uninstall.sh source
# 所有函数在此唯一定义，杜绝跨脚本重复实现导致的不一致
#
# v3.0.1 改进：
# - 修复已知良好模块数显示为总模块数的问题（改为仅统计启用模块）
# - WebUI saveGoodModules 与 common.sh 保存逻辑对齐（含禁用模块前缀）
#
# v3.0.0 改进（专业级升级）：
# - 嫌疑模块追踪：save_good_modules / detect_suspect_modules（BG 核心功能）
# - 三级渐进式救砖：嫌疑禁用 → 全量+脚本锁定 → APP 解冻
# - 脚本目录禁用：disable_script_dirs（全量救砖时锁定 service.d 等）
# - APP 解冻：unfreeze_apps（删除 package-restrictions.xml）
# - 安全文件 I/O：safe_write / safe_read

# 全局版本号（所有脚本统一引用）
RX_VERSION="v3.2.4"
RX_VERSION_CODE=324

# ============================================================
# 路径初始化
# ============================================================
_rescuex_init_paths() {
    # MODDIR 可由调用者预设（如 watchdog.sh），否则从 $0 推断
    if [ -z "$MODDIR" ]; then
        MODDIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
    fi
    # 兜底：尝试已知路径
    if [ -z "$MODDIR" ] || [ ! -d "$MODDIR" ]; then
        for d in /data/adb/modules/RescueX /data/adb/ksu/modules/RescueX /data/adb/ap/modules/RescueX /data/adb/ap_modules/RescueX; do
            if [ -d "$d" ]; then MODDIR="$d"; break; fi
        done
    fi

    SELF_ID="RescueX"
    STATE_DIR="$MODDIR/webroot/state"
    CONF_FILE="$STATE_DIR/config.conf"
    WHITELIST_FILE="$STATE_DIR/whitelist.conf"
    STATUS_FILE="$STATE_DIR/boot_status"
    STATUS_TMP="$STATE_DIR/.boot_status.tmp"
    JSON_FILE="$STATE_DIR/boot_status.json"
    LOG_FILE="$STATE_DIR/rescue.log"
    HISTORY_FILE="$STATE_DIR/boot_history"
    WATCHDOG_PID_FILE="$STATE_DIR/watchdog_pid"
    WATCHDOG_SCRIPT="$MODDIR/watchdog.sh"
    SNAPSHOT_DIR="$STATE_DIR/snapshots"
    AUTO_SNAPSHOT_FILE="$SNAPSHOT_DIR/auto-snap-latest.txt"
    AUTO_SNAPSHOT_SESSION_FILE="$STATE_DIR/auto_snapshot_session"
    MAX_MANUAL_SNAPSHOTS=5
    SCRIPT_RISK_ALERT_FILE="$STATE_DIR/script_risk_alert.conf"
    SCRIPT_RISK_QUARANTINE_DIR="$STATE_DIR/script_risk_quarantine"

    # v3.0.0: 嫌疑模块追踪
    GOOD_MODULES_FILE="$STATE_DIR/good_modules.list"   # 成功开机后的已知良好模块列表
    SUSPECT_LOG="$STATE_DIR/suspect_modules.log"         # 救砖时检测到的嫌疑模块日志

    # v3.0.0: 三级救砖 - 当前救砖级别追踪
    RESCUE_LEVEL_FILE="$STATE_DIR/rescue_level"          # 0=嫌疑禁用, 1=全量+脚本, 2=APP解冻


    # 补丁更新标记文件（持久化，跨重启保留）
    # 由 WebUI 或外部工具写入 "1" 表示处于补丁更新窗口期
    PATCH_FLAG_FILE="$STATE_DIR/patch_update_flag"
    PATCH_FAIL_COUNT_FILE="$STATE_DIR/patch_fail_count"
    PATCH_BACKUP_DIR="$STATE_DIR/patch_backup"

    # v2.7.0: 救砖禁用列表（记录救砖操作禁用的模块，供精确恢复）
    RESCUED_DISABLED_LIST="$STATE_DIR/rescued_disabled.list"

    # v2.7.0: 持久数据目录（模块更新时不会丢失）
    PERSIST_DIR="/data/adb/rescuex_data"

    MODULE_BASE="/data/adb/modules"
    MODULE_BASE_KSU=""
    MODULE_BASE_AP=""
    [ -d "/data/adb/ksu/modules" ] && MODULE_BASE_KSU="/data/adb/ksu/modules"
    # APatch 兼容：新版本用 /data/adb/ap/modules，早期版本用 /data/adb/ap_modules
    for _ap_dir in /data/adb/ap/modules /data/adb/ap_modules; do
        if [ -d "$_ap_dir" ]; then
            MODULE_BASE_AP="$_ap_dir"
            break
        fi
    done
    unset _ap_dir

    SAFE_CUSTOM_DIR_PREFIXES="$PERSIST_DIR $STATE_DIR $SNAPSHOT_DIR /data/local/tmp/RescueX"
}

# ============================================================
# 时间工具：uptime 单调时钟 + 智能日志时间
# ============================================================

# 读取 /proc/uptime 的整数秒部分（内核启动后的单调递增时间）
# 不依赖 RTC、不依赖系统时钟同步，在 post-fs-data 阶段即可用
# 返回值通过 stdout，失败返回 0
get_uptime_sec() {
    local up
    up=$(cat /proc/uptime 2>/dev/null | cut -d' ' -f1 | cut -d'.' -f1)
    case "$up" in ''|*[!0-9]*) echo 0 ;; *) echo "$up" ;; esac
}

# 智能日志时间：系统时钟正常时显示日期，异常时显示 uptime
# 解决 post-fs-data 阶段 RTC 未同步导致日志显示 1971 年的问题
# 阈值：1577836800 = 2020-01-01 00:00:00 UTC，小于此值视为时钟异常
#
# v2.6.0 兼容性修复（老牌遗留问题）：
# 原实现 `date '+%Y-%m-%d %H:%M:%S'` 输出含空格（如 "2026-07-16 12:34:56"），
# 写入 boot_history 后 [time] 字段被 compute_boot_stats 用 `${line%% *}` 切分时
# 只能取到 "[2026-07-16"，破坏统计解析。现统一输出无空格格式：
#   - 时钟正常：返回纯 epoch（无空格，可被 ${line%% *} 完整切出）
#   - 时钟异常：返回 uptime+Ns 格式（同样无空格）
# 日志可读性通过诊断报告的 date 转换保留（见 generate_report 内 date -d 调用）。
get_log_time() {
    local epoch up
    epoch=$(date +%s 2>/dev/null)
    case "$epoch" in ''|*[!0-9]*) epoch=0 ;; esac
    if [ "$epoch" -lt 1577836800 ]; then
        # 系统时钟异常（如 1971 年），用 uptime 显示相对时间
        up=$(get_uptime_sec)
        echo "uptime+${up}s"
    else
        # v2.6.0: 输出 epoch，无空格，便于 boot_history 字段解析
        echo "$epoch"
    fi
}

# ============================================================
# 日志（带自动轮转 + 智能时间戳）
# ============================================================
log() {
    # LOG_ENABLED 可能未被 read_config 设置（如 watchdog 触发前）
    if [ "${LOG_ENABLED:-true}" != "true" ]; then return; fi
    mkdir -p "${LOG_FILE%/*}" 2>/dev/null
    echo "[$(get_log_time)] $1" >> "$LOG_FILE"
    # 轮转：超 500KB 保留最后 200 行
    local sz
    sz=$(wc -c < "$LOG_FILE" 2>/dev/null)
    case "$sz" in
        ''|*[!0-9]*)
            # 极少数 toybox 不支持 wc -c，退回 stat -c%s，两者都不可用则跳过本次轮转检查
            sz=$(stat -c%s "$LOG_FILE" 2>/dev/null)
            case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
            ;;
    esac
    if [ "$sz" -gt 512000 ]; then
        tail -n 200 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
        echo "[$(get_log_time)] [日志已轮转]" >> "$LOG_FILE"
    fi
}

# ============================================================
# 持久化同步（v2.7.0 新增）
# 关键数据同步到模块外部目录，模块更新/重装后自动恢复
# ============================================================

# 同步关键持久数据到外部目录（模块更新时不会丢失）
sync_to_persist() {
    mkdir -p "$PERSIST_DIR" 2>/dev/null
    normalize_snapshot_storage
    for f in config.conf whitelist.conf boot_status boot_history patch_fail_count patch_update_flag rescued_disabled.list rescue_audit.log good_modules.list rescue_level auto_snapshot_session; do
        [ -f "$STATE_DIR/$f" ] && cp "$STATE_DIR/$f" "$PERSIST_DIR/$f" 2>/dev/null
    done
    # 快照目录
    if [ -d "$SNAPSHOT_DIR" ]; then
        mkdir -p "$PERSIST_DIR/snapshots" 2>/dev/null
        _sync_persist_snapshot_dir
        for snap in "$SNAPSHOT_DIR"/snap-*.txt "$SNAPSHOT_DIR"/auto-snap-*.txt; do
            [ -f "$snap" ] && cp "$snap" "$PERSIST_DIR/snapshots/" 2>/dev/null
        done
        prune_manual_snapshots_in_dir "$PERSIST_DIR/snapshots"
    fi
    chmod 0700 "$PERSIST_DIR" 2>/dev/null
}

# 从外部持久目录恢复数据（模块更新/重装后自动恢复）
restore_from_persist() {
    [ ! -d "$PERSIST_DIR" ] && return 1
    local restored=0
    for f in config.conf whitelist.conf boot_history patch_fail_count patch_update_flag rescued_disabled.list rescue_audit.log good_modules.list rescue_level auto_snapshot_session; do
        if [ -f "$PERSIST_DIR/$f" ] && [ ! -f "$STATE_DIR/$f" ]; then
            cp "$PERSIST_DIR/$f" "$STATE_DIR/$f" 2>/dev/null && restored=$((restored + 1))
        fi
    done
    # 快照恢复
    if [ -d "$PERSIST_DIR/snapshots" ]; then
        mkdir -p "$SNAPSHOT_DIR" 2>/dev/null
        for snap in "$PERSIST_DIR/snapshots"/snap-*.txt "$PERSIST_DIR/snapshots"/auto-snap-*.txt; do
            [ -f "$snap" ] || continue
            snap_name=$(basename "$snap")
            [ ! -f "$SNAPSHOT_DIR/$snap_name" ] && cp "$snap" "$SNAPSHOT_DIR/" 2>/dev/null && restored=$((restored + 1))
        done
        normalize_snapshot_storage
        prune_manual_snapshots_in_dir "$SNAPSHOT_DIR"
    fi
    # boot_status 特殊处理：合并累计字段
    if [ -f "$PERSIST_DIR/boot_status" ]; then
        _merge_persistent_boot_status
        restored=$((restored + 1))
    fi
    [ "$restored" -gt 0 ] && log "从持久目录恢复了 $restored 个文件"
    return 0
}

# 合并持久目录的 boot_status 累计字段到当前 boot_status
_merge_persistent_boot_status() {
    [ ! -f "$PERSIST_DIR/boot_status" ] && return
    [ ! -f "$STATUS_FILE" ] && return

    # 读取持久目录的累计值
    local persist_rescue_count=0 persist_last_rescue_time=0
    local k v
    while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        case "$k" in
            RESCUE_COUNT) persist_rescue_count="$v" ;;
            LAST_RESCUE_TIME) persist_last_rescue_time="$v" ;;
        esac
    done < "$PERSIST_DIR/boot_status"
    case "$persist_rescue_count" in ''|*[!0-9]*) persist_rescue_count=0 ;; esac
    case "$persist_last_rescue_time" in ''|*[!0-9]*) persist_last_rescue_time=0 ;; esac

    # 读取当前文件的值
    local cur_rescue_count=0 cur_last_rescue_time=0
    while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        case "$k" in
            RESCUE_COUNT) cur_rescue_count="$v" ;;
            LAST_RESCUE_TIME) cur_last_rescue_time="$v" ;;
        esac
    done < "$STATUS_FILE"
    case "$cur_rescue_count" in ''|*[!0-9]*) cur_rescue_count=0 ;; esac
    case "$cur_last_rescue_time" in ''|*[!0-9]*) cur_last_rescue_time=0 ;; esac

    # 取最大值合并
    local final_rescue_count=$cur_rescue_count
    local final_last_rescue_time=$cur_last_rescue_time
    [ "$persist_rescue_count" -gt "$cur_rescue_count" ] && final_rescue_count=$persist_rescue_count
    [ "$persist_last_rescue_time" -gt "$cur_last_rescue_time" ] && final_last_rescue_time=$persist_last_rescue_time

    # 如果有变化，更新当前文件
    if [ "$final_rescue_count" != "$cur_rescue_count" ] || [ "$final_last_rescue_time" != "$cur_last_rescue_time" ]; then
        # 读取所有字段并重写
        local boot_start=0 boot_end=0 service_started=0 fail_count=0 result=UNKNOWN
        local ota_detected=false boot_duration=0 uptime_start=0 uptime_end=0 patch_detected=false
        while IFS='=' read -r k v; do
            [ -z "$k" ] && continue
            case "$k" in
                BOOT_START) boot_start="$v" ;;
                BOOT_END) boot_end="$v" ;;
                SERVICE_STARTED) service_started="$v" ;;
                FAIL_COUNT) fail_count="$v" ;;
                LAST_BOOT_RESULT) result="$v" ;;
                OTA_DETECTED) ota_detected="$v" ;;
                BOOT_DURATION) boot_duration="$v" ;;
                UPTIME_START) uptime_start="$v" ;;
                UPTIME_END) uptime_end="$v" ;;
                PATCH_DETECTED) patch_detected="$v" ;;
            esac
        done < "$STATUS_FILE"

        local tmp="${STATUS_TMP}.$$"
        cat > "$tmp" << STATUS
BOOT_START=$boot_start
BOOT_END=$boot_end
SERVICE_STARTED=$service_started
FAIL_COUNT=$fail_count
LAST_BOOT_RESULT=$result
OTA_DETECTED=$ota_detected
RESCUE_COUNT=$final_rescue_count
LAST_RESCUE_TIME=$final_last_rescue_time
BOOT_DURATION=$boot_duration
UPTIME_START=$uptime_start
UPTIME_END=$uptime_end
PATCH_DETECTED=$patch_detected
STATUS
        sync "$tmp" 2>/dev/null
        mv "$tmp" "$STATUS_FILE"
        chmod 0600 "$STATUS_FILE" 2>/dev/null
        log "合并持久数据: RESCUE_COUNT=$final_rescue_count, LAST_RESCUE_TIME=$final_last_rescue_time"
    fi
}

# ============================================================
# 救砖审计日志（v2.7.0 新增）
# ============================================================

# 记录救砖操作审计日志
# 参数: <action_type> <detail>
log_rescue_action() {
    local action_type="$1"
    local detail="$2"
    local audit_file="$STATE_DIR/rescue_audit.log"
    mkdir -p "${audit_file%/*}" 2>/dev/null
    echo "[$(get_log_time)] $action_type | $detail" >> "$audit_file"
    # 轮转审计日志到 200 行
    local lc
    lc=$(wc -l < "$audit_file" 2>/dev/null || echo 0)
    case "$lc" in ''|*[!0-9]*) lc=0 ;; esac
    if [ "$lc" -gt 200 ]; then
        tail -n 200 "$audit_file" > "${audit_file}.tmp"
        mv "${audit_file}.tmp" "$audit_file"
    fi
    # 同步到持久目录
    [ -d "$PERSIST_DIR" ] && cp "$audit_file" "$PERSIST_DIR/rescue_audit.log" 2>/dev/null
}

# 列出救砖审计日志
list_rescue_audit() {
    local audit_file="$STATE_DIR/rescue_audit.log"
    [ -f "$audit_file" ] && cat "$audit_file" || echo "(无审计记录)"
}

# ============================================================
# 配置读取（一次性读入，避免多次 grep）
# ============================================================
read_config() {
    # 默认值
    REBOOT_THRESHOLD=3
    BOOT_TIMEOUT_SEC=90
    OTA_TIMEOUT_SEC=900
    ENABLED=true
    LOG_ENABLED=true
    DRY_RUN=false
    PROGRESSIVE_RESCUE=true
    AUTO_REENABLE=false
    USER_REBOOT_GRACE_SEC=30
    # v2.4 新增：补丁更新专属配置
    PATCH_UPDATE_TIMEOUT_SEC=180
    PATCH_FAIL_THRESHOLD=2
    PATCH_AUTO_ROLLBACK=true
    # 看门狗轮询间隔（秒），原硬编码为 2，现可配置（尤其利于 OTA 900s 长超时场景减少轮询次数）
    WATCHDOG_POLL_INTERVAL_SEC=2

    [ ! -f "$CONF_FILE" ] && return

    local k v
    while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        case "$k" in
            REBOOT_THRESHOLD) REBOOT_THRESHOLD="${v:-3}" ;;
            BOOT_TIMEOUT_SEC) BOOT_TIMEOUT_SEC="${v:-90}" ;;
            OTA_TIMEOUT_SEC) OTA_TIMEOUT_SEC="${v:-900}" ;;
            ENABLED) ENABLED="${v:-true}" ;;
            LOG_ENABLED) LOG_ENABLED="${v:-true}" ;;
            DRY_RUN) DRY_RUN="${v:-false}" ;;
            PROGRESSIVE_RESCUE) PROGRESSIVE_RESCUE="${v:-true}" ;;
            AUTO_REENABLE) AUTO_REENABLE="${v:-false}" ;;
            USER_REBOOT_GRACE_SEC) USER_REBOOT_GRACE_SEC="${v:-30}" ;;
            PATCH_UPDATE_TIMEOUT_SEC) PATCH_UPDATE_TIMEOUT_SEC="${v:-180}" ;;
            PATCH_FAIL_THRESHOLD) PATCH_FAIL_THRESHOLD="${v:-2}" ;;
            PATCH_AUTO_ROLLBACK) PATCH_AUTO_ROLLBACK="${v:-true}" ;;
            WATCHDOG_POLL_INTERVAL_SEC) WATCHDOG_POLL_INTERVAL_SEC="${v:-2}" ;;
        esac
    done < "$CONF_FILE"

    # 数字校验
    case "$REBOOT_THRESHOLD" in ''|*[!0-9]*) REBOOT_THRESHOLD=3 ;; esac
    case "$BOOT_TIMEOUT_SEC" in ''|*[!0-9]*) BOOT_TIMEOUT_SEC=90 ;; esac
    case "$OTA_TIMEOUT_SEC" in ''|*[!0-9]*) OTA_TIMEOUT_SEC=900 ;; esac
    case "$USER_REBOOT_GRACE_SEC" in ''|*[!0-9]*) USER_REBOOT_GRACE_SEC=30 ;; esac
    case "$PATCH_UPDATE_TIMEOUT_SEC" in ''|*[!0-9]*) PATCH_UPDATE_TIMEOUT_SEC=180 ;; esac
    case "$PATCH_FAIL_THRESHOLD" in ''|*[!0-9]*) PATCH_FAIL_THRESHOLD=2 ;; esac
    case "$WATCHDOG_POLL_INTERVAL_SEC" in ''|*[!0-9]*) WATCHDOG_POLL_INTERVAL_SEC=2 ;; esac

    # 范围限制（2>/dev/null 防止非数字比较报错）
    [ "$REBOOT_THRESHOLD" -lt 1 ] 2>/dev/null && REBOOT_THRESHOLD=1
    [ "$REBOOT_THRESHOLD" -gt 10 ] 2>/dev/null && REBOOT_THRESHOLD=10
    [ "$BOOT_TIMEOUT_SEC" -lt 30 ] 2>/dev/null && BOOT_TIMEOUT_SEC=30
    [ "$BOOT_TIMEOUT_SEC" -gt 600 ] 2>/dev/null && BOOT_TIMEOUT_SEC=600
    [ "$OTA_TIMEOUT_SEC" -lt 60 ] 2>/dev/null && OTA_TIMEOUT_SEC=60
    [ "$OTA_TIMEOUT_SEC" -gt 1800 ] 2>/dev/null && OTA_TIMEOUT_SEC=1800
    [ "$USER_REBOOT_GRACE_SEC" -lt 5 ] 2>/dev/null && USER_REBOOT_GRACE_SEC=5
    [ "$USER_REBOOT_GRACE_SEC" -gt 300 ] 2>/dev/null && USER_REBOOT_GRACE_SEC=300
    # 补丁超时：60-600 秒（1-10 分钟），介于普通开机和完整 OTA 之间
    [ "$PATCH_UPDATE_TIMEOUT_SEC" -lt 60 ] 2>/dev/null && PATCH_UPDATE_TIMEOUT_SEC=60
    [ "$PATCH_UPDATE_TIMEOUT_SEC" -gt 600 ] 2>/dev/null && PATCH_UPDATE_TIMEOUT_SEC=600
    # 补丁失败阈值：1-5 次
    [ "$PATCH_FAIL_THRESHOLD" -lt 1 ] 2>/dev/null && PATCH_FAIL_THRESHOLD=1
    [ "$PATCH_FAIL_THRESHOLD" -gt 5 ] 2>/dev/null && PATCH_FAIL_THRESHOLD=5
    # 看门狗轮询间隔：1-10 秒（原硬编码 2，过小在 OTA 长超时下轮询次数过多，过大影响及时性）
    [ "$WATCHDOG_POLL_INTERVAL_SEC" -lt 1 ] 2>/dev/null && WATCHDOG_POLL_INTERVAL_SEC=1
    [ "$WATCHDOG_POLL_INTERVAL_SEC" -gt 10 ] 2>/dev/null && WATCHDOG_POLL_INTERVAL_SEC=10
}

# ============================================================
# 白名单读取（安全过滤：只允许 [A-Za-z0-9._-]）
# ============================================================
read_whitelist() {
    WHITELIST=""
    [ ! -f "$WHITELIST_FILE" ] && return
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        # 去注释
        line="${line%%#*}"
        line=$(printf '%s' "$line" | tr -d ' \t\r' 2>/dev/null)
        [ -z "$line" ] && continue
        # 安全校验：只允许字母数字 . _ -
        case "$line" in
            *[!A-Za-z0-9._-]*) continue ;;
        esac
        WHITELIST="${WHITELIST}${line}
"
    done < "$WHITELIST_FILE"
}

# 判断模块是否在白名单（用 printf + grep -Fxq，O(1) 命令调用）
is_whitelisted() {
    [ -z "$WHITELIST" ] && return 1
    [ -z "$1" ] && return 1
    printf '%s\n' "$WHITELIST" | grep -Fxq -- "$1" 2>/dev/null
}

# ============================================================
# 命令可用性检测（部分 toybox 精简版不含 timeout/pkill -f 等）
# ============================================================
_HAS_TIMEOUT=""
_check_has_timeout() {
    if [ -z "$_HAS_TIMEOUT" ]; then
        if command -v timeout >/dev/null 2>&1; then
            _HAS_TIMEOUT="1"
        else
            _HAS_TIMEOUT="0"
        fi
    fi
}

# 按 cmdline 子串杀进程，等价于 pkill -f 的最小兜底实现
# 部分设备的 busybox pkill 不支持 -f 选项，改为手动遍历 /proc 匹配 cmdline
_kill_by_cmdline() {
    local pattern="$1" pid cmdline
    for p in /proc/[0-9]*; do
        pid="${p#/proc/}"
        [ -f "$p/cmdline" ] || continue
        cmdline=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
        case "$cmdline" in
            *"$pattern"*) kill -9 "$pid" 2>/dev/null ;;
        esac
    done
}

# 带超时地读取块设备前几个字节；优先用 timeout 命令，
# 不可用时用后台 dd + 轮询等待的方式手动实现超时，避免慢速 eMMC 卡死启动流程
# 用法: _dd_read_with_timeout <device> <timeout_sec>
_dd_read_with_timeout() {
    local dev="$1" tmo="${2:-2}"
    _check_has_timeout
    if [ "$_HAS_TIMEOUT" = "1" ]; then
        timeout "$tmo" dd if="$dev" bs=64 count=1 2>/dev/null
        return
    fi
    # 手动超时兜底：后台执行 dd，输出到临时文件，轮询等待或强制终止
    local out="${STATE_DIR:-/data/local/tmp}/.dd_timeout_$$.tmp"
    mkdir -p "${out%/*}" 2>/dev/null
    ( dd if="$dev" bs=64 count=1 2>/dev/null > "$out" ) &
    local dd_pid=$!
    local waited=0
    while [ "$waited" -lt "$tmo" ]; do
        if ! kill -0 "$dd_pid" 2>/dev/null; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    # 不论是超时还是自然结束，都先尝试 SIGKILL（若仍存活），再 wait 收割僵尸
    # 修复 Issue 1：原先仅在超时分支 kill，dd 在 kill -0 与 sleep 之间自然退出时会留下僵尸
    if kill -0 "$dd_pid" 2>/dev/null; then
        kill -9 "$dd_pid" 2>/dev/null
    fi
    wait "$dd_pid" 2>/dev/null  # 收割僵尸进程，避免子进程残留
    cat "$out" 2>/dev/null
    rm -f "$out" 2>/dev/null
}

# ============================================================
# OTA 检测（覆盖 A/B + BCB + update_engine + recovery）
# ============================================================
detect_ota() {
    # 方法1: 系统属性
    local ota_state
    ota_state=$(getprop sys.ota.update_state 2>/dev/null)
    [ -n "$ota_state" ] && [ "$ota_state" != "0" ] && return 0

    # 方法2: /cache/recovery/command
    if [ -f "/cache/recovery/command" ] && grep -q "update_package" "/cache/recovery/command" 2>/dev/null; then
        return 0
    fi

    # 方法3: A/B BCB (Bootloader Control Block)
    # 兼容多厂商路径：高通 bootdevice、联发科 by-name、平台 platform/*/by-name 变体
    local misc_dev=""
    for p in /dev/block/by-name/misc /dev/block/bootdevice/by-name/misc /dev/block/platform/*/by-name/misc /dev/block/platform/*/*/by-name/misc; do
        if [ -b "$p" ]; then
            misc_dev="$p"
            break
        fi
    done
    if [ -n "$misc_dev" ]; then
        # 优先用 timeout 防止慢速 eMMC 阻塞（Perf-1）；toybox 不保证提供 timeout，
        # 不可用时改用后台 dd + 手动看门狗的方式兜底，避免无限期阻塞启动流程
        if _dd_read_with_timeout "$misc_dev" 2 | strings | grep -q "boot-recovery"; then
            return 0
        fi
    fi

    # 方法4: /metadata/ota 标志
    if [ -f "/metadata/ota" ] || [ -f "/metadata/ota/update" ] || [ -f "/metadata/ota/delta" ]; then
        return 0
    fi

    # 方法5: A/B update_engine（仅当 slot_suffix 非空时才检查）
    local slot_suffix
    slot_suffix=$(getprop ro.boot.slot_suffix 2>/dev/null)
    if [ -n "$slot_suffix" ]; then
        local ue_dir="/data/misc/update_engine/prefs"
        [ -f "$ue_dir/update-engine-running" ] && return 0
        if [ -f "$ue_dir/active-slot" ]; then
            local active_slot cur_slot
            active_slot=$(cat "$ue_dir/active-slot" 2>/dev/null | tr -d '_')
            cur_slot=$(getprop ro.boot.slot_suffix 2>/dev/null | tr -d '_')
            if [ -n "$active_slot" ] && [ -n "$cur_slot" ] && [ "$active_slot" != "$cur_slot" ]; then
                return 0
            fi
        fi
    fi

    # 方法6: recovery last_status
    if [ -f "/cache/recovery/last_status" ] 2>/dev/null; then
        if grep -qE "installing|updating" "/cache/recovery/last_status" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# ============================================================
# 补丁更新检测（v2.4 新增）
# 识别 ColorOS/MIUI/HyperOS/OnePlus/原生 System Update 等上层系统更新
# 与底层 OTA（detect_ota）隔离，互不干扰
# 返回 0=检测到补丁更新 1=未检测到
# ============================================================
detect_patch_update() {
    # 优先级 1: 用户/外部工具手动设置的持久标记
    if [ -f "$PATCH_FLAG_FILE" ]; then
        local flag
        flag=$(cat "$PATCH_FLAG_FILE" 2>/dev/null | tr -d ' \t\r\n')
        [ "$flag" = "1" ] && return 0
    fi

    # 优先级 2: ColorOS / OPPO 系统更新
    # 路径：/data/oplus/ota、/cache/ota、oplus 侧属性
    if [ -f "/data/oplus/ota/update_status" ] 2>/dev/null; then
        return 0
    fi
    if [ -d "/data/oplus/ota_package" ] 2>/dev/null; then
        return 0
    fi
    local oplus_state
    oplus_state=$(getprop sys.ota.update_state 2>/dev/null)
    if [ -n "$oplus_state" ] && [ "$oplus_state" != "0" ] && [ "$oplus_state" != "IDLE" ]; then
        return 0
    fi
    # OPPO/realme 的 ro.build.ota 可能存在升级标记
    if getprop ro.oppo.update_state 2>/dev/null | grep -qi "updating\|installing"; then
        return 0
    fi

    # 优先级 3: MIUI / HyperOS 系统更新
    # 路径：/data/miui/ota、/cache/miui
    if [ -f "/data/miui/ota/update.status" ] 2>/dev/null; then
        return 0
    fi
    if [ -d "/data/miui/ota_package" ] 2>/dev/null; then
        return 0
    fi
    if getprop sys.miui.update_state 2>/dev/null | grep -qi "updating\|installing"; then
        return 0
    fi

    # 优先级 4: vivo / OriginOS 系统更新
    if [ -f "/data/bbk/ota/update_status" ] 2>/dev/null; then
        return 0
    fi
    if getprop sys.vivo.update_state 2>/dev/null | grep -qi "updating\|installing"; then
        return 0
    fi

    # 优先级 5: Samsung One UI 系统更新
    if [ -f "/data/system/updates.xml" ] 2>/dev/null; then
        return 0
    fi

    # 优先级 6: 通用 Android System Update（Package Installer 上层更新）
    if [ -f "/data/ota/last_install" ] 2>/dev/null; then
        # 检查最近修改时间，5 分钟内视为补丁更新窗口
        local now mtime
        now=$(date +%s 2>/dev/null)
        mtime=$(stat -c %Y "/data/ota/last_install" 2>/dev/null || stat -f %m "/data/ota/last_install" 2>/dev/null || echo 0)
        case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
        if [ "$now" != "0" ] && [ "$mtime" != "0" ] && [ "$((now - mtime))" -lt 300 ]; then
            return 0
        fi
    fi

    # 优先级 7: /cache 分区下的更新包残留
    if [ -f "/cache/update.zip" ] 2>/dev/null || [ -f "/cache/ota.zip" ] 2>/dev/null; then
        return 0
    fi

    # 优先级 8: 检测 PackageInstaller 上层应用更新标记
    if [ -f "/data/system/packages.xml.backup" ] 2>/dev/null; then
        return 0
    fi

    return 1
}

# 读取补丁失败计数（独立于普通启动失败计数）
read_patch_fail_count() {
    PATCH_FAIL_COUNT=0
    if [ -f "$PATCH_FAIL_COUNT_FILE" ]; then
        local c
        c=$(cat "$PATCH_FAIL_COUNT_FILE" 2>/dev/null | tr -d ' \t\r\n')
        case "$c" in ''|*[!0-9]*) c=0 ;; esac
        PATCH_FAIL_COUNT=$c
    fi
}

# 写入补丁失败计数
write_patch_fail_count() {
    echo "$1" > "$PATCH_FAIL_COUNT_FILE" 2>/dev/null
    sync "$PATCH_FAIL_COUNT_FILE" 2>/dev/null
}

# 设置补丁更新标记（供 WebUI 调用）
set_patch_flag() {
    echo "1" > "$PATCH_FLAG_FILE" 2>/dev/null
    sync "$PATCH_FLAG_FILE" 2>/dev/null
    log "补丁更新标记已设置（手动）"
    log_rescue_action "PATCH_FLAG_SET" "manual"
}

# 清除补丁更新标记（启动成功后调用）
clear_patch_flag() {
    rm -f "$PATCH_FLAG_FILE" 2>/dev/null
    write_patch_fail_count 0
    log "补丁更新标记已清除（启动成功）"
}

manual_clear_patch_flag() {
    clear_patch_flag
    log_rescue_action "PATCH_FLAG_CLEAR" "manual"
}

# ============================================================
# WebUI 手动入口与安全写入
# ============================================================

_write_file_atomic() {
    local target="$1"
    local content="$2"
    [ -z "$target" ] && return 1
    mkdir -p "${target%/*}" 2>/dev/null
    local tmp="${target}.tmp.$$"
    printf '%s' "$content" > "$tmp" 2>/dev/null || return 1
    sync "$tmp" 2>/dev/null
    mv -f "$tmp" "$target" 2>/dev/null || return 1
    return 0
}

_normalize_safe_dir() {
    local dir="$1"
    [ -z "$dir" ] && return 1
    case "$dir" in
        */) printf '%s' "${dir%/}" ;;
        *) printf '%s' "$dir" ;;
    esac
}

is_safe_custom_dir() {
    local dir normalized prefix norm_prefix
    dir="$1"
    [ -z "$dir" ] && return 1
    case "$dir" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$dir" in
        *".."*|*"*"*|*"?"*|*"["*|*"]"*|*" "*|*"\t"*) return 1 ;;
    esac

    normalized=$(_normalize_safe_dir "$dir") || return 1
    for prefix in $SAFE_CUSTOM_DIR_PREFIXES; do
        norm_prefix=$(_normalize_safe_dir "$prefix") || continue
        [ "$normalized" = "$norm_prefix" ] && return 0
        case "$normalized" in
            "$norm_prefix"/*) return 0 ;;
        esac
    done
    return 1
}

save_custom_dirs_file() {
    local input_file="$1"
    [ -z "$input_file" ] || [ ! -f "$input_file" ] && return 1

    local line dir perm normalized safe_count=0 reject_count=0
    local tmp_content="$STATE_DIR/.custom_dirs.content.$$"
    : > "$tmp_content" 2>/dev/null || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        dir=$(printf '%s' "$line" | awk '{print $1}')
        perm=$(printf '%s' "$line" | awk '{print $2}')
        [ -z "$dir" ] || [ -z "$perm" ] && { reject_count=$((reject_count + 1)); continue; }
        case "$perm" in 700|750|755|770) ;; *) reject_count=$((reject_count + 1)); continue ;; esac
        if is_safe_custom_dir "$dir"; then
            normalized=$(_normalize_safe_dir "$dir")
            printf '%s %s\n' "$normalized" "$perm" >> "$tmp_content"
            safe_count=$((safe_count + 1))
        else
            reject_count=$((reject_count + 1))
        fi
    done < "$input_file"

    if _write_file_atomic "$STATE_DIR/custom_dirs.conf" "$(cat "$tmp_content" 2>/dev/null)"; then
        chmod 0600 "$STATE_DIR/custom_dirs.conf" 2>/dev/null
        log_rescue_action "CUSTOM_DIRS_SAVE" "saved=$safe_count,rejected=$reject_count"
        rm -f "$tmp_content" 2>/dev/null
        printf 'SAVED=%s\nREJECTED=%s\n' "$safe_count" "$reject_count"
        return 0
    fi
    rm -f "$tmp_content" 2>/dev/null
    return 1
}

clear_suspect_log() {
    : > "$SUSPECT_LOG" 2>/dev/null || return 1
    chmod 0600 "$SUSPECT_LOG" 2>/dev/null
    log_rescue_action "SUSPECT_LOG_CLEAR" "manual"
    return 0
}

clear_script_risk_alert() {
    rm -f "$SCRIPT_RISK_ALERT_FILE" 2>/dev/null
    log_rescue_action "SCRIPT_RISK_ALERT_CLEAR" "manual"
    return 0
}

_list_current_module_ids() {
    local base mod_id mod_dir
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -z "$base" ] || [ ! -d "$base" ] && continue
        for mod_dir in "$base"/*/; do
            [ ! -d "$mod_dir" ] && continue
            mod_id=$(basename "$mod_dir")
            [ "$mod_id" = "$SELF_ID" ] && continue
            [ -f "${mod_dir}remove" ] && continue
            case "$mod_id" in *[!A-Za-z0-9._-]*) continue ;; esac
            printf '%s\n' "$mod_id"
        done
    done
}

prune_suspect_log() {
    [ -f "$SUSPECT_LOG" ] || return 0

    local current_file="${STATE_DIR}/.current_modules.$$"
    local tmp_log="${SUSPECT_LOG}.tmp.$$"
    local line mod_id kept=0 removed=0

    _list_current_module_ids | sort -u > "$current_file" 2>/dev/null
    : > "$tmp_log" 2>/dev/null || {
        rm -f "$current_file" 2>/dev/null
        return 1
    }

    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
            \?*) mod_id="${line#\?}" ;;
            +*) mod_id="${line#+}" ;;
            :*) mod_id="${line#:}" ;;
            *) mod_id="$line" ;;
        esac
        case "$mod_id" in ''|*[!A-Za-z0-9._-]*) removed=$((removed + 1)); continue ;; esac
        if grep -qx "$mod_id" "$current_file" 2>/dev/null; then
            printf '%s\n' "$line" >> "$tmp_log"
            kept=$((kept + 1))
        else
            removed=$((removed + 1))
            log "移除过期嫌疑记录: $mod_id"
        fi
    done < "$SUSPECT_LOG"

    mv -f "$tmp_log" "$SUSPECT_LOG"
    chmod 0600 "$SUSPECT_LOG" 2>/dev/null
    rm -f "$current_file" 2>/dev/null
    [ "$removed" -gt 0 ] && log_rescue_action "SUSPECT_LOG_PRUNE" "kept=$kept,removed=$removed"
    return 0
}

reset_rescue_level_state() {
    write_rescue_level 0
    log_rescue_action "RESCUE_LEVEL_RESET" "manual"
    return 0
}

manual_save_good_modules() {
    save_good_modules || return 1
    local enabled_count=0
    if [ -f "$GOOD_MODULES_FILE" ]; then
        enabled_count=$(grep -cv '^:' "$GOOD_MODULES_FILE" 2>/dev/null || echo 0)
    fi
    log_rescue_action "GOOD_MODULES_SAVE" "manual,enabled=$enabled_count"
    printf '%s\n' "$enabled_count"
    return 0
}

manual_lock_script_dirs() {
    disable_script_dirs
    printf 'LOCKED=%s\n' "${SCRIPT_DIRS_LOCKED_LAST:-0}"
    return 0
}

manual_unfreeze_apps() {
    app_unfreeze
    printf '%s\n' "${APP_UNFREEZE_LAST_RESULT:-SKIP}"
    return 0
}

manual_take_snapshot() {
    local mode="${1:-manual}"
    local snap
    snap=$(take_snapshot "$mode") || return 1
    case "$mode" in
        auto) log_rescue_action "AUTO_SNAPSHOT_SAVE" "$(basename "$snap")" ;;
        *) log_rescue_action "SNAPSHOT_SAVE" "$(basename "$snap")" ;;
    esac
    printf '%s\n' "$snap"
    return 0
}

get_manual_snapshot_limit() {
    local limit="${MAX_MANUAL_SNAPSHOTS:-12}"
    case "$limit" in ''|*[!0-9]*) limit=12 ;; esac
    [ "$limit" -lt 1 ] 2>/dev/null && limit=1
    echo "$limit"
}

prune_manual_snapshots_in_dir() {
    local dir="$1"
    local limit count snap
    [ -d "$dir" ] || return 0
    limit=$(get_manual_snapshot_limit)
    count=0
    for snap in $(ls -1 "$dir"/snap-*.txt 2>/dev/null | sort -r); do
        [ -f "$snap" ] || continue
        count=$((count + 1))
        if [ "$count" -gt "$limit" ]; then
            rm -f "$snap" 2>/dev/null
        fi
    done
    return 0
}

is_legacy_auto_snapshot_file() {
    local snap_file="$1"
    [ -f "$snap_file" ] || return 1
    grep -q '^# 类型: auto$' "$snap_file" 2>/dev/null
}

_sync_persist_snapshot_dir() {
    local persisted snap_name
    [ -d "$PERSIST_DIR/snapshots" ] || return 0
    for persisted in "$PERSIST_DIR/snapshots"/snap-*.txt "$PERSIST_DIR/snapshots"/auto-snap-*.txt; do
        [ -f "$persisted" ] || continue
        snap_name=$(basename "$persisted")
        [ -f "$SNAPSHOT_DIR/$snap_name" ] && continue
        rm -f "$persisted" 2>/dev/null
    done
    return 0
}

delete_persisted_snapshot() {
    local snap_name="$1"
    [ -n "$snap_name" ] || return 0
    [ -d "$PERSIST_DIR/snapshots" ] || return 0
    rm -f "$PERSIST_DIR/snapshots/$snap_name" 2>/dev/null
    return 0
}

normalize_snapshot_storage() {
    local snap latest_legacy_auto=""
    [ -d "$SNAPSHOT_DIR" ] || return 0

    for snap in $(ls -1 "$SNAPSHOT_DIR"/snap-*.txt 2>/dev/null | sort -r); do
        [ -f "$snap" ] || continue
        if is_legacy_auto_snapshot_file "$snap"; then
            [ -n "$latest_legacy_auto" ] || latest_legacy_auto="$snap"
        fi
    done

    if [ -n "$latest_legacy_auto" ] && [ ! -f "$AUTO_SNAPSHOT_FILE" ]; then
        mv -f "$latest_legacy_auto" "$AUTO_SNAPSHOT_FILE" 2>/dev/null
        chmod 0600 "$AUTO_SNAPSHOT_FILE" 2>/dev/null
    fi

    for snap in $(ls -1 "$SNAPSHOT_DIR"/snap-*.txt 2>/dev/null | sort -r); do
        [ -f "$snap" ] || continue
        is_legacy_auto_snapshot_file "$snap" && rm -f "$snap" 2>/dev/null
    done
    return 0
}

get_auto_snapshot_session_key() {
    local boot_start=0 uptime_start=0 last_result=""
    local k v
    if [ -f "$STATUS_FILE" ]; then
        while IFS='=' read -r k v || [ -n "$k$v" ]; do
            [ -z "$k" ] && continue
            case "$k" in
                BOOT_START) boot_start="$v" ;;
                UPTIME_START) uptime_start="$v" ;;
                LAST_BOOT_RESULT) last_result="$v" ;;
            esac
        done < "$STATUS_FILE"
    fi
    case "$boot_start" in ''|*[!0-9]*) boot_start=0 ;; esac
    case "$uptime_start" in ''|*[!0-9]*) uptime_start=0 ;; esac

    if [ "$boot_start" -gt 0 ] 2>/dev/null; then
        echo "boot:$boot_start"
        return 0
    fi
    if [ "$uptime_start" -gt 0 ] 2>/dev/null; then
        echo "uptime:$uptime_start"
        return 0
    fi
    if [ -n "$last_result" ]; then
        echo "result:$last_result"
        return 0
    fi
    echo "uptime:$(get_uptime_sec)"
}

auto_snapshot_already_taken() {
    local session_key existing_key
    [ -f "$AUTO_SNAPSHOT_FILE" ] || return 1
    [ -f "$AUTO_SNAPSHOT_SESSION_FILE" ] || return 1
    session_key=$(get_auto_snapshot_session_key)
    existing_key=$(cat "$AUTO_SNAPSHOT_SESSION_FILE" 2>/dev/null)
    [ -n "$session_key" ] || return 1
    [ "$existing_key" = "$session_key" ]
}

write_auto_snapshot_session() {
    local session_key="$1"
    [ -n "$session_key" ] || return 1
    printf '%s\n' "$session_key" > "$AUTO_SNAPSHOT_SESSION_FILE" 2>/dev/null || return 1
    chmod 0600 "$AUTO_SNAPSHOT_SESSION_FILE" 2>/dev/null
    return 0
}

manual_restore_snapshot() {
    local snap_file="$1"
    case "$snap_file" in
        "$SNAPSHOT_DIR"/snap-*.txt|"$AUTO_SNAPSHOT_FILE") ;;
        *) return 1 ;;
    esac
    restore_snapshot "$snap_file" || return 1
    log_rescue_action "SNAPSHOT_RESTORE" "$(basename "$snap_file")"
    printf 'OK\n'
    return 0
}

manual_delete_snapshot() {
    local snap_file="$1"
    case "$snap_file" in
        "$SNAPSHOT_DIR"/snap-*.txt) ;;
        *) return 1 ;;
    esac
    delete_snapshot "$snap_file"
    log_rescue_action "SNAPSHOT_DELETE" "$(basename "$snap_file")"
    printf 'OK\n'
    return 0
}

manual_restore_good_modules_baseline() {
    restore_good_modules_baseline
}

manual_generate_rescue_decision_report() {
    generate_rescue_decision_report
}

manual_clear_script_risk_alert() {
    clear_script_risk_alert
    printf 'OK\n'
    return 0
}

send_root_notification() {
    local title="$1"
    local text="$2"
    [ -z "$title" ] && return 1
    [ -z "$text" ] && return 1
    command -v cmd >/dev/null 2>&1 || return 1
    cmd notification post -S bigtext -t "$title" RescueX "$text" >/dev/null 2>&1 && return 0
    cmd notification post -t "$title" RescueX "$text" >/dev/null 2>&1 && return 0
    return 1
}

_write_script_risk_alert() {
    local module_id="$1"
    local script_path="$2"
    local reason="$3"
    local action="$4"
    local detected_at
    detected_at=$(get_log_time)
    _write_file_atomic "$SCRIPT_RISK_ALERT_FILE" "DETECTED=1
MODULE_ID=${module_id}
SCRIPT_PATH=${script_path}
REASON=${reason}
ACTION=${action}
DETECTED_AT=${detected_at}
NOTIFIED=0
" || return 1
    chmod 0600 "$SCRIPT_RISK_ALERT_FILE" 2>/dev/null
    return 0
}

_mark_script_risk_alert_notified() {
    [ -f "$SCRIPT_RISK_ALERT_FILE" ] || return 1
    local tmp_file="$SCRIPT_RISK_ALERT_FILE.tmp.$$"
    local changed=0 k v
    : > "$tmp_file" 2>/dev/null || return 1
    while IFS='=' read -r k v || [ -n "$k$v" ]; do
        [ -z "$k" ] && continue
        if [ "$k" = "NOTIFIED" ]; then
            printf 'NOTIFIED=1\n' >> "$tmp_file"
            changed=1
        else
            printf '%s=%s\n' "$k" "$v" >> "$tmp_file"
        fi
    done < "$SCRIPT_RISK_ALERT_FILE"
    [ "$changed" -eq 1 ] || printf 'NOTIFIED=1\n' >> "$tmp_file"
    mv -f "$tmp_file" "$SCRIPT_RISK_ALERT_FILE" 2>/dev/null || return 1
    chmod 0600 "$SCRIPT_RISK_ALERT_FILE" 2>/dev/null
    return 0
}

notify_pending_script_risk_alert() {
    [ -f "$SCRIPT_RISK_ALERT_FILE" ] || return 1
    local module_id="unknown" script_path="unknown" reason="high-risk script" action_taken="blocked" notified=0 k v
    while IFS='=' read -r k v || [ -n "$k$v" ]; do
        [ -z "$k" ] && continue
        case "$k" in
            MODULE_ID) module_id="$v" ;;
            SCRIPT_PATH) script_path="$v" ;;
            REASON) reason="$v" ;;
            ACTION) action_taken="$v" ;;
            NOTIFIED) notified="$v" ;;
        esac
    done < "$SCRIPT_RISK_ALERT_FILE"
    [ "$notified" = "1" ] && return 0
    send_root_notification "RescueX 安全提醒" "已拦截高风险脚本: ${module_id} (${reason})" || return 1
    log "已发送高风险脚本通知: $module_id | $script_path | $reason"
    _mark_script_risk_alert_notified
    return 0
}

detect_destructive_script_content() {
    local target="$1"
    [ -f "$target" ] || return 1
    grep -Eiv '^[[:space:]]*#' "$target" 2>/dev/null | grep -Eiq '(^|[;&|[:space:]])rm[[:space:]]+-[[:alnum:]]*r[[:alnum:]]*f[[:space:]]+/((data|cache|metadata|persist)(/|[[:space:]]|$)|sdcard([/[:space:]]|$)|storage(/emulated)?(/|[[:space:]]|$))' && {
        echo 'rm-rf-sensitive-path'
        return 0
    }
    grep -Eiv '^[[:space:]]*#' "$target" 2>/dev/null | grep -Eiq 'find[[:space:]]+/((data|cache|metadata)(/|[[:space:]]|$)|sdcard([/[:space:]]|$)|storage(/emulated)?(/|[[:space:]]|$)).*-delete' && {
        echo 'find-delete-sensitive-path'
        return 0
    }
    grep -Eiv '^[[:space:]]*#' "$target" 2>/dev/null | grep -Eiq '(^|[;&|[:space:]])(mkfs|mke2fs|make_f2fs|newfs_msdos|wipefs|blkdiscard)([[:space:]]|$)' && {
        echo 'format-command'
        return 0
    }
    grep -Eiv '^[[:space:]]*#' "$target" 2>/dev/null | grep -Eiq 'dd[[:space:]].*of=/dev/(block|mmcblk|nvme|sd[a-z])' && {
        echo 'raw-block-write'
        return 0
    }
    grep -Eiv '^[[:space:]]*#' "$target" 2>/dev/null | grep -Eiq '(recovery|twrp|toybox)[[:space:]].*(wipe|format)|(^|[;&|[:space:]])sm[[:space:]]+format([[:space:]]|$)|(^|[;&|[:space:]])vdc[[:space:]].*format' && {
        echo 'wipe-or-format-invocation'
        return 0
    }
    return 1
}

_disable_module_by_dir() {
    local module_dir="$1"
    [ -d "$module_dir" ] || return 1
    touch "$module_dir/disable" 2>/dev/null || return 1
    chmod 000 "$module_dir/post-fs-data.sh" "$module_dir/service.sh" "$module_dir/post-mount.sh" "$module_dir/boot-completed.sh" 2>/dev/null
    return 0
}

_quarantine_script_file() {
    local target="$1"
    [ -f "$target" ] || return 1
    mkdir -p "$SCRIPT_RISK_QUARANTINE_DIR" 2>/dev/null
    chmod 000 "$target" 2>/dev/null
    cp "$target" "$SCRIPT_RISK_QUARANTINE_DIR/$(basename "$target").$(date +%s 2>/dev/null || echo 0).blocked" 2>/dev/null
    return 0
}

scan_and_block_destructive_scripts() {
    local hits=0 base mod_dir mod_id candidate reason rel label
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -z "$base" ] || [ ! -d "$base" ] && continue
        for mod_dir in "$base"/*/; do
            [ -d "$mod_dir" ] || continue
            mod_id=$(basename "$mod_dir")
            [ "$mod_id" = "$SELF_ID" ] && continue
            [ -f "${mod_dir}disable" ] && continue
            case "$mod_id" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
            for rel in post-fs-data.sh service.sh post-mount.sh boot-completed.sh service.d post-fs-data.d post-mount.d boot-completed.d; do
                candidate="${mod_dir}${rel}"
                if [ -f "$candidate" ]; then
                    reason=$(detect_destructive_script_content "$candidate" 2>/dev/null) || continue
                    _disable_module_by_dir "$mod_dir"
                    _quarantine_script_file "$candidate"
                    _write_script_risk_alert "$mod_id" "$candidate" "$reason" "module-disabled"
                    log "拦截高风险脚本模块: $mod_id | $candidate | $reason"
                    log_rescue_action "SCRIPT_RISK_BLOCK" "$mod_id|$candidate|$reason"
                    hits=$((hits + 1))
                    break
                elif [ -d "$candidate" ]; then
                    for label in "$candidate"/*.sh "$candidate"/*; do
                        [ -f "$label" ] || continue
                        reason=$(detect_destructive_script_content "$label" 2>/dev/null) || continue
                        _disable_module_by_dir "$mod_dir"
                        _quarantine_script_file "$label"
                        _write_script_risk_alert "$mod_id" "$label" "$reason" "module-disabled"
                        log "拦截高风险脚本模块: $mod_id | $label | $reason"
                        log_rescue_action "SCRIPT_RISK_BLOCK" "$mod_id|$label|$reason"
                        hits=$((hits + 1))
                        break
                    done
                    [ "$hits" -gt 0 ] && break
                fi
            done
        done
    done

    for label in /data/adb/post-fs-data.d /data/adb/service.d /data/adb/post-mount.d /data/adb/boot-completed.d /data/adb/ksu/service.d /data/adb/ap/service.d; do
        [ -d "$label" ] || continue
        for candidate in "$label"/*.sh "$label"/*; do
            [ -f "$candidate" ] || continue
            reason=$(detect_destructive_script_content "$candidate" 2>/dev/null) || continue
            _quarantine_script_file "$candidate"
            _write_script_risk_alert "global-script" "$candidate" "$reason" "script-blocked"
            log "拦截高风险全局脚本: $candidate | $reason"
            log_rescue_action "SCRIPT_RISK_BLOCK" "global-script|$candidate|$reason"
            hits=$((hits + 1))
        done
    done

    printf '%s\n' "$hits"
    return 0
}

# 补丁回滚逻辑（轻量级，不清整机数据）
# v2.4 核心防数据丢失机制
patch_rollback() {
    log "===== 触发补丁回滚（轻量级）====="

    # 策略 1: 如果存在补丁前快照，恢复模块状态（不动用户数据）
    if [ -d "$PATCH_BACKUP_DIR" ]; then
        local snap
        snap=$(ls -t "$PATCH_BACKUP_DIR"/snap-*.txt 2>/dev/null | head -1)
        if [ -n "$snap" ] && [ -f "$snap" ]; then
            log "找到补丁前快照: $(basename "$snap")，恢复模块状态"
            restore_snapshot "$snap"
            log "补丁回滚完成（模块状态已恢复，用户数据保留）"
            # 清除补丁标记和失败计数
            clear_patch_flag
            return 0
        fi
    fi

    # 策略 2: 无快照时，仅禁用最近安装的非白名单模块（渐进式）
    log "无补丁前快照，执行渐进式禁用最近模块"
    read_whitelist
    progressive_rescue 5

    # 清除补丁标记，避免循环
    clear_patch_flag
    log "补丁回滚完成（已禁用最近模块，用户数据保留）"
    return 0
}

# ============================================================
# 启动失败判定
# ============================================================

# 判断上次启动是否真的失败（考虑首次安装、看门狗救砖、用户主动重启的时间窗）
# 返回 0=真失败  1=非失败
# 依赖：PREV_* 变量（需先调用 read_previous_status）、USER_REBOOT_GRACE_SEC（需先调用 read_config）
is_real_boot_failure() {
    # 首次安装（INIT 状态）不计入失败
    [ "$PREV_BOOT_RESULT" = "INIT" ] && return 1
    # 无历史记录（BOOT_START=0）不计入失败
    [ "$PREV_BOOT_START" = "0" ] && return 1
    # 上次是看门狗救砖，已处理，不再计入失败
    [ "$PREV_BOOT_RESULT" = "RESCUED" ] && return 1
    # v3.0.0 BUG FIX: 移除 [ "$PREV_SERVICE_STARTED" = "1" ] && return 1
    # 原逻辑把 SERVICE_STARTED=1 等同于启动成功，但 service.sh 可能只执行了
    # mark_service_started() 就被中断（如测试模块触发重启、系统崩溃等），
    # 此时 BOOT_END=0、result=BOOTING，实际启动并未完成。
    # 正确判定应依赖 BOOT_END（service.sh 完整执行后才会写入非零值），
    # 而非 SERVICE_STARTED（仅表示 service.sh 开始执行过）。
    # BOOT_END 有值 = service.sh 完整执行 = 启动完成
    [ "$PREV_BOOT_END" != "0" ] && return 1
    # service.sh 没执行 = 启动中途失败 或 用户主动重启
    # 用时间窗区分：BOOT_START 距现在很近 = 用户主动重启
    local now elapsed
    now=$(date +%s)
    elapsed=$((now - PREV_BOOT_START))
    # 时钟合理性校验：elapsed 为负或超过 7 天，视为时钟异常，跳过时间窗判定
    # （时钟异常时无法可靠区分用户重启 vs 真实失败，保守计为非失败，避免误触发救砖）
    if [ "$elapsed" -lt 0 ] || [ "$elapsed" -gt 604800 ]; then
        log "时钟异常（elapsed=$elapsed），跳过时间窗判定，不计入失败"
        return 1
    fi
    # LOG-004: -lt 改为 -le，等于宽限期也不计入失败
    if [ "$elapsed" -le "$USER_REBOOT_GRACE_SEC" ]; then
        log "上次启动仅 $elapsed 秒，疑似用户主动重启，不计入失败"
        return 1
    fi
    # 时间窗之外，service.sh 也没执行 = 真的启动失败
    return 0
}

# ============================================================
# 状态文件原子写入
# ============================================================

# 全量写入状态（用于 post-fs-data 初始化）
# 参数: <result> <fail_count> <ota_detected> <service_started> <rescue_count> <last_rescue_time> [boot_start] [uptime_start] [patch_detected]
write_status() {
    local result="${1:-UNKNOWN}"
    local fail_count="${2:-0}"
    local ota_detected="${3:-false}"
    local service_started="${4:-0}"
    local rescue_count="${5:-0}"
    local last_rescue_time="${6:-0}"
    local boot_start="${7:-$(date +%s)}"
    local uptime_start="${8:-0}"
    local patch_detected="${9:-false}"

    mkdir -p "${STATUS_FILE%/*}" 2>/dev/null

    # 用 PID 后缀避免多进程并发写同一个临时文件
    # PATCH_DETECTED 现作为标准字段随主状态一起原子写入，不再靠事后 grep+append
    # 追加（那样会在 watchdog.sh 的 2 秒轮询窗口内造成短暂的状态不一致）
    local tmp="${STATUS_TMP}.$$"
    cat > "$tmp" << STATUS
BOOT_START=$boot_start
BOOT_END=0
SERVICE_STARTED=$service_started
FAIL_COUNT=$fail_count
LAST_BOOT_RESULT=$result
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
    # SEC-005: 运行时创建的文件显式设置权限
    chmod 0600 "$STATUS_FILE" 2>/dev/null
    _write_status_json "$boot_start" 0 "$service_started" "$fail_count" "$result" "$ota_detected" "$rescue_count" "$last_rescue_time" 0 "$uptime_start" 0 "$patch_detected"

    # 记录历史
    echo "[$(get_log_time)] START | fail=$fail_count | ota=$ota_detected | result=$result" >> "$HISTORY_FILE"
    _truncate_history

    # v2.7.0: 同步到持久目录
    sync_to_persist
}

# 增量更新状态（用于 service.sh 标记成功，保留其他字段）
# 参数: <boot_end> <service_started> <result> <fail_count> [uptime_end]
# boot_duration 由 uptime_end - uptime_start 计算（不依赖 RTC）
update_status_fields() {
    local boot_end="${1:-0}"
    local service_started="${2:-0}"
    local result="${3:-SUCCESS}"
    local fail_count="${4:-0}"
    local uptime_end="${5:-0}"

    # 读取现有字段（含 PATCH_DETECTED，本函数不改变补丁检测状态，只是原样保留）
    local boot_start=0 ota_detected=false rescue_count=0 last_rescue_time=0 uptime_start=0 patch_detected=false
    if [ -f "$STATUS_FILE" ]; then
        local k v
        while IFS='=' read -r k v; do
            [ -z "$k" ] && continue
            case "$k" in
                BOOT_START) boot_start="$v" ;;
                OTA_DETECTED) ota_detected="$v" ;;
                RESCUE_COUNT) rescue_count="$v" ;;
                LAST_RESCUE_TIME) last_rescue_time="$v" ;;
                UPTIME_START) uptime_start="$v" ;;
                PATCH_DETECTED) patch_detected="$v" ;;
            esac
        done < "$STATUS_FILE"
    fi

    case "$boot_start" in ''|*[!0-9]*) boot_start=0 ;; esac
    case "$rescue_count" in ''|*[!0-9]*) rescue_count=0 ;; esac
    case "$last_rescue_time" in ''|*[!0-9]*) last_rescue_time=0 ;; esac
    case "$uptime_start" in ''|*[!0-9]*) uptime_start=0 ;; esac
    case "$uptime_end" in ''|*[!0-9]*) uptime_end=0 ;; esac

    # 用 uptime 计算真实启动耗时（不依赖 RTC，即使时钟是 1971 年也准确）
    local boot_duration=0
    if [ "$uptime_start" -gt 0 ] && [ "$uptime_end" -gt 0 ] && [ "$uptime_end" -ge "$uptime_start" ]; then
        boot_duration=$((uptime_end - uptime_start))
        # 合理性校验：5 秒 ~ 1 小时
        if [ "$boot_duration" -lt 5 ] || [ "$boot_duration" -gt 3600 ]; then
            boot_duration=0
        fi
    fi

    # 用 PID 后缀避免多进程并发写同一个临时文件
    local tmp="${STATUS_TMP}.$$"
    cat > "$tmp" << STATUS
BOOT_START=$boot_start
BOOT_END=$boot_end
SERVICE_STARTED=$service_started
FAIL_COUNT=$fail_count
LAST_BOOT_RESULT=$result
OTA_DETECTED=$ota_detected
RESCUE_COUNT=$rescue_count
LAST_RESCUE_TIME=$last_rescue_time
BOOT_DURATION=$boot_duration
UPTIME_START=$uptime_start
UPTIME_END=$uptime_end
PATCH_DETECTED=$patch_detected
STATUS

    sync "$tmp" 2>/dev/null
    mv "$tmp" "$STATUS_FILE"
    # SEC-005: 运行时创建的文件显式设置权限
    chmod 0600 "$STATUS_FILE" 2>/dev/null

    _write_status_json "$boot_start" "$boot_end" "$service_started" "$fail_count" "$result" "$ota_detected" "$rescue_count" "$last_rescue_time" "$boot_duration" "$uptime_start" "$uptime_end" "$patch_detected"
}

# 内部：写 JSON 状态
# SEC-004: 归一化布尔字段（确保 JSON 中为 true/false 而非 True/False/1/0）
_write_status_json() {
    local boot_start="$1" boot_end="$2" service_started="$3" fail_count="$4"
    local result="$5" ota_detected="$6" rescue_count="$7" last_rescue_time="$8" boot_duration="$9"
    local uptime_start="${10}" uptime_end="${11}" patch_detected="${12:-false}"
    # SEC-004: 归一化布尔字段（确保 JSON 中为 true/false 而非 True/False/1/0）
    case "$ota_detected" in true|1|yes) ota_detected=true ;; *) ota_detected=false ;; esac
    case "$patch_detected" in true|1|yes) patch_detected=true ;; *) patch_detected=false ;; esac
    # 同步到持久目录
    sync_to_persist
    local jtmp="${JSON_FILE}.tmp.$$"
    cat > "$jtmp" << JSON
{
  "boot_start": $boot_start,
  "boot_end": $boot_end,
  "service_started": $service_started,
  "fail_count": $fail_count,
  "last_boot_result": "$result",
  "ota_detected": $ota_detected,
  "rescue_count": $rescue_count,
  "last_rescue_time": $last_rescue_time,
  "boot_duration": $boot_duration,
  "uptime_start": $uptime_start,
  "uptime_end": $uptime_end,
  "patch_detected": $patch_detected,
  "updated_at": "$(get_log_time)"
}
JSON
    sync "$jtmp" 2>/dev/null
    mv "$jtmp" "$JSON_FILE"
    # SEC-005: 运行时创建的文件显式设置权限
    chmod 0600 "$JSON_FILE" 2>/dev/null
}

# 内部：截断历史文件到 100 行
_truncate_history() {
    local lc
    lc=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
    case "$lc" in ''|*[!0-9]*) lc=0 ;; esac
    if [ "$lc" -gt 100 ]; then
        tail -n 100 "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
        mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    fi
}

# 读取上次状态（填充 PREV_* 变量）
read_previous_status() {
    PREV_BOOT_START=0
    PREV_BOOT_END=0
    PREV_SERVICE_STARTED=0
    PREV_FAIL_COUNT=0
    PREV_BOOT_RESULT="UNKNOWN"
    PREV_OTA_DETECTED="false"
    PREV_RESCUE_COUNT=0
    PREV_LAST_RESCUE_TIME=0
    PREV_PATCH_DETECTED="false"

    [ ! -f "$STATUS_FILE" ] && return

    local k v
    while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        case "$k" in
            BOOT_START) PREV_BOOT_START="$v" ;;
            BOOT_END) PREV_BOOT_END="$v" ;;
            SERVICE_STARTED) PREV_SERVICE_STARTED="$v" ;;
            FAIL_COUNT) PREV_FAIL_COUNT="$v" ;;
            LAST_BOOT_RESULT) PREV_BOOT_RESULT="$v" ;;
            OTA_DETECTED) PREV_OTA_DETECTED="$v" ;;
            RESCUE_COUNT) PREV_RESCUE_COUNT="$v" ;;
            LAST_RESCUE_TIME) PREV_LAST_RESCUE_TIME="$v" ;;
            PATCH_DETECTED) PREV_PATCH_DETECTED="$v" ;;
        esac
    done < "$STATUS_FILE"

    case "$PREV_FAIL_COUNT" in ''|*[!0-9]*) PREV_FAIL_COUNT=0 ;; esac
    case "$PREV_BOOT_START" in ''|*[!0-9]*) PREV_BOOT_START=0 ;; esac
    case "$PREV_BOOT_END" in ''|*[!0-9]*) PREV_BOOT_END=0 ;; esac
    case "$PREV_SERVICE_STARTED" in ''|*[!0-9]*) PREV_SERVICE_STARTED=0 ;; esac
    case "$PREV_RESCUE_COUNT" in ''|*[!0-9]*) PREV_RESCUE_COUNT=0 ;; esac
    case "$PREV_LAST_RESCUE_TIME" in ''|*[!0-9]*) PREV_LAST_RESCUE_TIME=0 ;; esac
}

# 修正 post-fs-data 阶段因 NTP 未同步导致 LAST_RESCUE_TIME 为 1971 年异常值的问题
# 在 post-fs-data 和 service.sh 中均会调用（双保险）
# 仅当时钟已恢复正常时才执行修正，确保不引入错误值
fix_last_rescue_time() {
    local now lrt
    now=$(date +%s 2>/dev/null)
    case "$now" in ''|*[!0-9]*) return ;; esac
    [ "$now" -le 1577836800 ] && return

    if [ ! -f "$STATUS_FILE" ]; then return; fi
    lrt=$(grep "^LAST_RESCUE_TIME=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    case "$lrt" in ''|*[!0-9]*) return ;; esac
    [ "$lrt" -eq 0 ] && return
    [ "$lrt" -ge 1577836800 ] && return

    local tmp="${STATUS_TMP}.$$"
    while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        [ "$k" = "LAST_RESCUE_TIME" ] && echo "LAST_RESCUE_TIME=$now" || echo "$k=$v"
    done < "$STATUS_FILE" > "$tmp"
    sync "$tmp" 2>/dev/null
    mv "$tmp" "$STATUS_FILE"
    chmod 0600 "$STATUS_FILE" 2>/dev/null
    log "已修正 LAST_RESCUE_TIME: $lrt → $now"
}

# ============================================================
# 模块操作
# ============================================================

# 禁用单个模块（考虑白名单 + DRY_RUN）
# 返回: 0=成功 1=参数错误 2=白名单 3=已禁用
disable_module_safe() {
    local mod_dir="$1"
    local mod_id="$2"
    [ -z "$mod_dir" ] || [ -z "$mod_id" ] && return 1
    [ "$mod_id" = "$SELF_ID" ] && return 1
    is_whitelisted "$mod_id" && return 2
    [ -f "${mod_dir}disable" ] && return 3

    if [ "$DRY_RUN" = "true" ]; then
        log "[DRY_RUN] 将禁用: $mod_id"
        return 0
    fi
    if touch "${mod_dir}disable" 2>/dev/null; then
        log "已禁用: $mod_id"
        # v2.7.0: 记录到救砖禁用列表（供精确恢复使用）
        echo "$mod_id" >> "$RESCUED_DISABLED_LIST" 2>/dev/null
        return 0
    fi
    log "禁用失败: $mod_id"
    return 1
}

# 注意：reenable_all 内联了恢复逻辑，不再调用此函数
# 保留定义供未来使用
_enable_module_safe() {
    local mod_dir="$1"
    local mod_id="$2"
    [ -z "$mod_dir" ] || [ -z "$mod_id" ] && return 1
    [ "$mod_id" = "$SELF_ID" ] && return 1
    [ ! -f "${mod_dir}disable" ] && return 3
    if rm -f "${mod_dir}disable" 2>/dev/null; then
        log "已恢复: $mod_id"
        return 0
    fi
    log "恢复失败: $mod_id"
    return 1
}

# 渐进式救砖：禁用最近安装的 N 个模块（用 ls -t 替代 stat+sort，可移植）
progressive_rescue() {
    local count="${1:-3}"
    case "$count" in ''|*[!0-9]*) count=3 ;; esac
    [ "$count" -lt 1 ] 2>/dev/null && count=1
    [ "$count" -gt 20 ] 2>/dev/null && count=20

    read_whitelist  # 确保白名单已加载
    log "渐进式救砖：禁用最近 $count 个模块"

    # v2.7.0: 救砖前自动拍快照
    local auto_snap
    auto_snap=$(take_snapshot auto)
    [ -n "$auto_snap" ] && log "救砖前自动快照: $(basename "$auto_snap")"

    local disabled=0
    local base mod_id mod_dir modules
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -z "$base" ] || [ ! -d "$base" ] && continue
        [ "$disabled" -ge "$count" ] && break
        # ls -t 按修改时间倒序，可移植（toybox/busybox 均支持）
        modules=$(ls -t "$base" 2>/dev/null)
        for mod_id in $modules; do
            [ -z "$mod_id" ] && continue
            [ "$disabled" -ge "$count" ] && break
            mod_dir="$base/$mod_id/"
            [ ! -d "$mod_dir" ] && continue
            disable_module_safe "$mod_dir" "$mod_id" && disabled=$((disabled + 1))
        done
    done
    log "渐进式救砖完成: 禁用 $disabled 个"
    log_rescue_action "PROGRESSIVE_RESCUE" "disabled=$disabled, count=$count"
}

# 全量救砖：禁用所有非白名单模块
full_rescue() {
    read_whitelist  # 确保白名单已加载
    log "全量救砖：禁用所有非白名单模块"

    # v2.7.0: 救砖前自动拍快照
    local auto_snap
    auto_snap=$(take_snapshot auto)
    [ -n "$auto_snap" ] && log "救砖前自动快照: $(basename "$auto_snap")"

    local disabled=0 skipped=0
    local base mod_id mod_dir
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -z "$base" ] || [ ! -d "$base" ] && continue
        for mod_dir in "$base"/*/; do
            [ ! -d "$mod_dir" ] && continue
            mod_id=$(basename "$mod_dir")
            [ "$mod_id" = "$SELF_ID" ] && { skipped=$((skipped + 1)); continue; }
            is_whitelisted "$mod_id" && { skipped=$((skipped + 1)); log "  跳过白名单: $mod_id"; continue; }
            [ -f "${mod_dir}disable" ] && { skipped=$((skipped + 1)); continue; }
            if [ "$DRY_RUN" = "true" ]; then
                log "[DRY_RUN] 将禁用: $mod_id"
                disabled=$((disabled + 1))
            else
                touch "${mod_dir}disable" 2>/dev/null && { log "已禁用: $mod_id"; disabled=$((disabled + 1)); echo "$mod_id" >> "$RESCUED_DISABLED_LIST" 2>/dev/null; } || log "禁用失败: $mod_id"
            fi
        done
    done
    log "全量救砖完成: 禁用 $disabled 个, 跳过 $skipped 个"
    log_rescue_action "FULL_RESCUE" "disabled=$disabled, skipped=$skipped"
}

# 恢复被救砖禁用的模块（仅恢复 rescued_disabled.list 中记录的）
# v2.7.0 LOG-002 修复：原实现恢复所有被禁用模块（含用户手动禁用的），
# 现改为仅恢复救砖操作本身禁用的模块
reenable_all() {
    log "恢复救砖禁用的模块"
    local enabled=0

    # 优先使用 rescued_disabled.list（精确恢复）
    if [ -f "$RESCUED_DISABLED_LIST" ]; then
        local mod_id
        while IFS= read -r mod_id || [ -n "$mod_id" ]; do
            [ -z "$mod_id" ] && continue
            case "$mod_id" in \#*) continue ;; esac
            case "$mod_id" in *[!A-Za-z0-9._-]*) continue ;; esac
            [ "$mod_id" = "$SELF_ID" ] && continue
            # 在所有 base 中查找
            local found_dir=""
            for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
                [ -z "$base" ] || [ ! -d "$base" ] && continue
                if [ -d "$base/$mod_id" ] && [ -f "$base/$mod_id/disable" ]; then
                    found_dir="$base/$mod_id"
                    break
                fi
            done
            if [ -n "$found_dir" ]; then
                rm -f "${found_dir}/disable" 2>/dev/null && { log "已恢复: $mod_id"; enabled=$((enabled + 1)); }
            fi
        done < "$RESCUED_DISABLED_LIST"
        rm -f "$RESCUED_DISABLED_LIST" 2>/dev/null
        log "精确恢复完成: $enabled 个（基于 rescued_disabled.list）"
    else
        # 兜底：无 rescued_disabled.list 时恢复所有被禁用模块
        log "未找到 rescued_disabled.list，回退到恢复所有被禁用模块"
        local base mod_id mod_dir
        for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
            [ -z "$base" ] || [ ! -d "$base" ] && continue
            for mod_dir in "$base"/*/; do
                [ ! -d "$mod_dir" ] && continue
                mod_id=$(basename "$mod_dir")
                [ "$mod_id" = "$SELF_ID" ] && continue
                [ ! -f "${mod_dir}disable" ] && continue
                rm -f "${mod_dir}disable" 2>/dev/null && { log "已恢复: $mod_id"; enabled=$((enabled + 1)); }
            done
        done
        log "兜底恢复完成: $enabled 个"
    fi
}

# ============================================================
# 看门狗管理
# ============================================================

# 安全停止看门狗（按 PID + cmdline 验证，防 PID 复用误杀）
stop_watchdog() {
    if [ -f "$WATCHDOG_PID_FILE" ]; then
        local wd_pid
        wd_pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
        case "$wd_pid" in
            ''|*[!0-9]*) wd_pid=0 ;;
        esac
        if [ "$wd_pid" != "0" ] && kill -0 "$wd_pid" 2>/dev/null; then
            local cmdline
            cmdline=$(cat /proc/$wd_pid/cmdline 2>/dev/null | tr '\0' ' ')
            case "$cmdline" in
                *watchdog.sh*|*"${MODDIR}/watchdog"*)
                    kill "$wd_pid" 2>/dev/null
                    local i=0
                    while [ $i -lt 5 ] && kill -0 "$wd_pid" 2>/dev/null; do
                        sleep 1
                        i=$((i + 1))
                    done
                    # kill -9 前复查 cmdline，避免 PID 复用误杀
                    if kill -0 "$wd_pid" 2>/dev/null; then
                        local c2
                        c2=$(cat /proc/$wd_pid/cmdline 2>/dev/null | tr '\0' ' ')
                        case "$c2" in
                            *watchdog.sh*|*"${MODDIR}/watchdog"*) kill -9 "$wd_pid" 2>/dev/null ;;
                            *) log "警告：PID $wd_pid 已变为非看门狗进程，跳过 kill -9" ;;
                        esac
                    fi
                    log "看门狗已停止 (PID=$wd_pid)"
                    ;;
                *)
                    log "警告：PID $wd_pid cmdline='$cmdline' 非看门狗，跳过"
                    ;;
            esac
        fi
        rm -f "$WATCHDOG_PID_FILE"
    fi
    # 兜底：按脚本路径 pkill（部分 busybox pkill 不支持 -f，失败时手动兜底）
    if command -v pkill >/dev/null 2>&1 && pkill -f "${MODDIR}/watchdog.sh" 2>/dev/null; then
        :
    else
        _kill_by_cmdline "${MODDIR}/watchdog.sh"
    fi
}

# 看门狗触发的救砖逻辑（在 watchdog.sh 子进程中调用）
watchdog_trigger() {
    log "[WD] 看门狗超时触发救砖"

    # 重新读取配置和白名单（触发时配置可能已变）
    read_config
    read_whitelist

    # v3.0.0: 使用三级渐进式救砖
    three_level_rescue

    # 标记状态为 RESCUED，更新救砖计数
    local rescue_count=0
    if [ -f "$STATUS_FILE" ]; then
        local rc
        rc=$(grep "^RESCUE_COUNT=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
        case "$rc" in ''|*[!0-9]*) rc=0 ;; esac
        rescue_count=$((rc + 1))
    else
        rescue_count=1
    fi
    local now
    now=$(date +%s)

    local tmp="${STATUS_TMP}.$$"
    cat > "$tmp" << STAT
BOOT_START=$now
BOOT_END=0
SERVICE_STARTED=0
FAIL_COUNT=0
LAST_BOOT_RESULT=RESCUED
OTA_DETECTED=false
RESCUE_COUNT=$rescue_count
LAST_RESCUE_TIME=$now
BOOT_DURATION=0
UPTIME_START=0
UPTIME_END=0
PATCH_DETECTED=false
STAT
    sync "$tmp" 2>/dev/null
    mv "$tmp" "$STATUS_FILE"
    # SEC-005: 运行时创建的文件显式设置权限
    chmod 0600 "$STATUS_FILE" 2>/dev/null

    _write_status_json "$now" 0 0 0 "RESCUED" false "$rescue_count" "$now" 0 0 0 false

    # v2.5: 记录救砖事件到 history，便于统计面板绘制时间线
    echo "[$(get_log_time)] RESCUE | count=$rescue_count | result=RESCUED" >> "$HISTORY_FILE"
    _truncate_history

    # v2.7.0: 记录审计日志
    log_rescue_action "WATCHDOG_TRIGGER" "timeout, full_rescue executed"

    # v2.7.0: 同步到持久目录
    sync_to_persist

    log "[WD] 救砖完成，sync 后重启"
    # sync 加 3 秒超时，防止文件系统损坏时无限阻塞（Sec-2）
    sync &
    SYNC_PID=$!
    sleep 3
    kill -9 $SYNC_PID 2>/dev/null
    wait $SYNC_PID 2>/dev/null

    # 多级重启兜底（Compat-2: Android 12+ sysrq 可能被禁用）
    setprop sys.powerctl reboot 2>/dev/null
    sleep 5
    reboot 2>/dev/null
    sleep 5
    # 兜底: 强制重启到 recovery 再重启
    setprop sys.powerctl reboot,recovery 2>/dev/null
    sleep 10
    # 最后手段: sysrq-trigger（需先开启 sysrq）
    # SEC-003: sysrq 值从 1 改为 128（仅允许重启命令，不允许所有命令）
    echo 128 > /proc/sys/kernel/sysrq 2>/dev/null
    echo b > /proc/sysrq-trigger 2>/dev/null
}

# ============================================================
# 模块列表扫描（供 WebUI 模块选择器使用）
# 输出格式：mod_id|enabled|manager
# ============================================================
list_all_modules() {
    local base manager mod_id mod_dir enabled
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -z "$base" ] || [ ! -d "$base" ] && continue
        case "$base" in
            */ksu/modules) manager="KSU" ;;
            */ap/modules|*/ap_modules) manager="APatch" ;;
            *) manager="Magisk" ;;
        esac
        for mod_dir in "$base"/*/; do
            [ ! -d "$mod_dir" ] && continue
            mod_id=$(basename "$mod_dir")
            [ "$mod_id" = "$SELF_ID" ] && continue
            case "$mod_id" in *[!A-Za-z0-9._-]*) continue ;; esac
            # 跳过 update 目录、remove 标记
            [ -f "${mod_dir}remove" ] && continue
            if [ -f "${mod_dir}disable" ]; then
                enabled="0"
            else
                enabled="1"
            fi
            echo "${mod_id}|${enabled}|${manager}"
        done
    done
}

# 列出当前被禁用的模块（供 WebUI 展示）
list_disabled_modules() {
    local base mod_id mod_dir
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -z "$base" ] || [ ! -d "$base" ] && continue
        for mod_dir in "$base"/*/; do
            [ ! -d "$mod_dir" ] && continue
            [ -f "${mod_dir}disable" ] || continue
            mod_id=$(basename "$mod_dir")
            [ "$mod_id" = "$SELF_ID" ] && continue
            case "$mod_id" in *[!A-Za-z0-9._-]*) continue ;; esac
            echo "$mod_id"
        done
    done
}

# ============================================================
# 模块快照与回滚（Feature-2）
# ============================================================

# 拍快照：记录当前所有模块的 enable/disable 状态
# 参数: [manual|auto]
take_snapshot() {
    mkdir -p "$SNAPSHOT_DIR" 2>/dev/null
    local mode="${1:-manual}"
    local snap_file tmp_file label session_key
    case "$mode" in
        auto)
            snap_file="$AUTO_SNAPSHOT_FILE"
            label="auto"
            if auto_snapshot_already_taken; then
                echo "$snap_file"
                return 0
            fi
            session_key=$(get_auto_snapshot_session_key)
            ;;
        *)
            snap_file="$SNAPSHOT_DIR/snap-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown).txt"
            label="manual"
            ;;
    esac
    tmp_file="${snap_file}.tmp.$$"
    {
        echo "# RescueX 模块快照 - $(date 2>/dev/null)"
        echo "# 类型: $label"
        echo "# 格式: mod_id=enabled|disabled"
        local base mod_id mod_dir
        for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
            [ -z "$base" ] || [ ! -d "$base" ] && continue
            for mod_dir in "$base"/*/; do
                [ ! -d "$mod_dir" ] && continue
                mod_id=$(basename "$mod_dir")
                [ "$mod_id" = "$SELF_ID" ] && continue
                case "$mod_id" in *[!A-Za-z0-9._-]*) continue ;; esac
                if [ -f "${mod_dir}disable" ]; then
                    echo "${mod_id}=disabled"
                else
                    echo "${mod_id}=enabled"
                fi
            done
        done
    } > "$tmp_file" 2>/dev/null || return 1
    sync "$tmp_file" 2>/dev/null
    mv -f "$tmp_file" "$snap_file" 2>/dev/null || return 1
    chmod 0600 "$snap_file" 2>/dev/null
    [ "$label" = "auto" ] && write_auto_snapshot_session "$session_key"
    [ "$label" = "manual" ] && prune_manual_snapshots_in_dir "$SNAPSHOT_DIR"
    echo "$snap_file"
}

# 回滚到指定快照
# 参数: <snap_file>
restore_snapshot() {
    local snap_file="$1"
    [ ! -f "$snap_file" ] && return 1

    local mod_id state mod_dir
    while IFS='=' read -r mod_id state; do
        [ -z "$mod_id" ] && continue
        case "$mod_id" in \#*) continue ;; esac
        [ -z "$state" ] && continue
        # 安全校验
        case "$mod_id" in *[!A-Za-z0-9._-]*) continue ;; esac
        case "$state" in enabled|disabled) ;; *) continue ;; esac

        # 在三个 base 中查找模块
        local found_dir=""
        for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
            [ -z "$base" ] || [ ! -d "$base" ] && continue
            if [ -d "$base/$mod_id" ]; then
                found_dir="$base/$mod_id"
                break
            fi
        done
        [ -z "$found_dir" ] && continue

        if [ "$state" = "enabled" ]; then
            rm -f "${found_dir}/disable" 2>/dev/null
        else
            touch "${found_dir}/disable" 2>/dev/null
        fi
    done < "$snap_file"
    return 0
}

# 列出所有快照
list_snapshots() {
    [ ! -d "$SNAPSHOT_DIR" ] && return
    normalize_snapshot_storage
    prune_manual_snapshots_in_dir "$SNAPSHOT_DIR"
    ls -1 "$SNAPSHOT_DIR"/snap-*.txt 2>/dev/null | sort -r
}

# 删除快照
# 参数: <snap_file>
delete_snapshot() {
    local snap_name=""
    case "$1" in
        "$SNAPSHOT_DIR"/snap-*.txt)
            [ -f "$1" ] || return 1
            snap_name=$(basename "$1")
            rm -f "$1" 2>/dev/null || return 1
            delete_persisted_snapshot "$snap_name"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

restore_good_modules_baseline() {
    [ -f "$GOOD_MODULES_FILE" ] || return 1

    local line mod_id desired_state found_dir base changed=0 skipped=0
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
            :*) mod_id="${line#:}"; desired_state="disabled" ;;
            *) mod_id="$line"; desired_state="enabled" ;;
        esac
        case "$mod_id" in ''|*[!A-Za-z0-9._-]*) skipped=$((skipped + 1)); continue ;; esac
        [ "$mod_id" = "$SELF_ID" ] && continue

        found_dir=""
        for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
            [ -z "$base" ] || [ ! -d "$base" ] && continue
            if [ -d "$base/$mod_id" ]; then
                found_dir="$base/$mod_id"
                break
            fi
        done
        [ -z "$found_dir" ] && { skipped=$((skipped + 1)); continue; }

        if [ "$desired_state" = "enabled" ]; then
            if [ -f "${found_dir}/disable" ]; then
                rm -f "${found_dir}/disable" 2>/dev/null && changed=$((changed + 1))
            fi
        else
            if [ ! -f "${found_dir}/disable" ]; then
                touch "${found_dir}/disable" 2>/dev/null && changed=$((changed + 1))
            fi
        fi
    done < "$GOOD_MODULES_FILE"

    log "已恢复稳定基线: changed=$changed skipped=$skipped"
    log_rescue_action "BASELINE_RESTORE" "changed=$changed,skipped=$skipped"
    printf 'CHANGED=%s\nSKIPPED=%s\n' "$changed" "$skipped"
    return 0
}

generate_rescue_decision_report() {
    local rescue_level=0 fail_count=0 threshold=0 boot_result="UNKNOWN" patch_detected="false"
    local baseline_total=0 baseline_enabled=0 suspect_new=0 suspect_reenabled=0 suspect_uncertain=0
    local suspect_lines=""
    local recommendation=""

    read_config
    read_status
    read_rescue_level

    fail_count="${FAIL_COUNT:-0}"
    threshold="${REBOOT_THRESHOLD:-0}"
    boot_result="${BOOT_RESULT:-UNKNOWN}"
    patch_detected="${PATCH_DETECTED:-false}"

    if [ -f "$GOOD_MODULES_FILE" ]; then
        baseline_total=$(grep -cve '^\s*$' "$GOOD_MODULES_FILE" 2>/dev/null || echo 0)
        baseline_enabled=$(grep -cve '^[:#]' "$GOOD_MODULES_FILE" 2>/dev/null || echo 0)
    fi

    if [ -f "$SUSPECT_LOG" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -z "$line" ] && continue
            case "$line" in
                \#*) continue ;;
                +*) suspect_reenabled=$((suspect_reenabled + 1)) ;;
                \?*) suspect_uncertain=$((suspect_uncertain + 1)) ;;
                *) suspect_new=$((suspect_new + 1)) ;;
            esac
            suspect_lines="${suspect_lines}${line}\n"
        done < "$SUSPECT_LOG"
    fi

    case "$rescue_level" in
        0) rescue_level="0: 精准嫌疑禁用" ;;
        1) rescue_level="1: 全量模块禁用 + 脚本锁定" ;;
        2) rescue_level="2: APP 解冻" ;;
        *) rescue_level="0: 精准嫌疑禁用" ;;
    esac

    if [ "$baseline_total" -eq 0 ]; then
        recommendation="当前缺少稳定基线。设备稳定后先保存当前模块列表，再观察后续启动结果。"
    elif [ "$suspect_new" -gt 0 ]; then
        recommendation="优先保持新增嫌疑模块处于禁用状态，完成一次稳定启动后再逐个复核。"
    elif [ "$suspect_reenabled" -gt 0 ]; then
        recommendation="重点检查最近重新启用的模块，必要时回到稳定基线后逐个恢复。"
    elif [ "$patch_detected" = "true" ]; then
        recommendation="当前处于补丁相关窗口，优先核对补丁模块和 update 缓存恢复结果。"
    elif [ "$fail_count" -ge "$threshold" ] 2>/dev/null; then
        recommendation="失败计数已经达到阈值，建议立即恢复稳定基线并检查白名单与脚本目录。"
    else
        recommendation="当前适合先保留现状，继续观察下一次完整启动，并保留最新诊断报告。"
    fi

    {
        echo "=========================================="
        echo "  RescueX 救援决策报告"
        echo "  版本: $RX_VERSION (code=$RX_VERSION_CODE)"
        echo "  生成时间: $(get_log_time)"
        echo "=========================================="
        echo ""
        echo "=== 当前判断 ==="
        echo "启动结果: $boot_result"
        echo "连续失败次数: $fail_count / $threshold"
        echo "当前救砖级别: $rescue_level"
        echo "补丁窗口: $patch_detected"
        echo ""
        echo "=== 稳定基线 ==="
        echo "基线总数: $baseline_total"
        echo "基线启用模块: $baseline_enabled"
        echo ""
        echo "=== 嫌疑模块统计 ==="
        echo "新增嫌疑: $suspect_new"
        echo "重新启用嫌疑: $suspect_reenabled"
        echo "不确定参考: $suspect_uncertain"
        if [ -n "$suspect_lines" ]; then
            echo ""
            echo "=== 嫌疑清单 ==="
            printf '%b' "$suspect_lines"
        fi
        echo ""
        echo "=== 建议动作 ==="
        echo "$recommendation"
        echo "=========================================="
    }
}

# ============================================================
# 单模块操作（v2.7.0 新增，供 WebUI 使用）
# ============================================================

# 获取单个模块详细信息（供 WebUI 使用）
# 输出: name|version|author|description|enabled|manager
module_info() {
    local mod_id="$1"
    [ -z "$mod_id" ] && return 1
    case "$mod_id" in *[!A-Za-z0-9._-]*) return 1 ;; esac

    local found_dir="" manager=""
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -z "$base" ] || [ ! -d "$base" ] && continue
        if [ -d "$base/$mod_id" ]; then
            found_dir="$base/$mod_id"
            case "$base" in
                */ksu/modules) manager="KSU" ;;
                */ap/modules|*/ap_modules) manager="APatch" ;;
                *) manager="Magisk" ;;
            esac
            break
        fi
    done
    [ -z "$found_dir" ] && return 1

    local name="" version="" author="" description=""
    if [ -f "$found_dir/module.prop" ]; then
        local k v
        while IFS='=' read -r k v; do
            [ -z "$k" ] && continue
            case "$k" in
                name) name="$v" ;;
                version) version="$v" ;;
                author) author="$v" ;;
                description) description="$v" ;;
            esac
        done < "$found_dir/module.prop"
    fi

    local enabled="1"
    [ -f "${found_dir}/disable" ] && enabled="0"

    echo "${name:-$mod_id}|${version:-?}|${author:-?}|${description:-?}|${enabled}|${manager}"
}

# 切换单个模块启用/禁用状态（供 WebUI 使用）
toggle_single_module() {
    local mod_id="$1"
    local action="$2"  # enable or disable
    [ -z "$mod_id" ] || [ -z "$action" ] && return 1
    case "$mod_id" in *[!A-Za-z0-9._-]*) return 1 ;; esac
    [ "$mod_id" = "$SELF_ID" ] && return 1

    local found_dir=""
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -z "$base" ] || [ ! -d "$base" ] && continue
        if [ -d "$base/$mod_id" ]; then
            found_dir="$base/$mod_id"
            break
        fi
    done
    [ -z "$found_dir" ] && return 1

    case "$action" in
        enable)
            [ ! -f "${found_dir}/disable" ] && return 2  # already enabled
            rm -f "${found_dir}/disable" 2>/dev/null
            log "手动启用模块: $mod_id"
            log_rescue_action "MANUAL_ENABLE" "$mod_id"
            return 0
            ;;
        disable)
            [ -f "${found_dir}/disable" ] && return 2  # already disabled
            touch "${found_dir}/disable" 2>/dev/null
            log "手动禁用模块: $mod_id"
            log_rescue_action "MANUAL_DISABLE" "$mod_id"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ============================================================
# 完整状态导出（v2.7.0 新增，供 WebUI 导出功能使用）
# ============================================================

# 导出完整状态（供 WebUI 导出功能使用）
export_full_state() {
    local out_file="$1"
    [ -z "$out_file" ] && out_file="$STATE_DIR/rescuex_export.txt"

    {
        echo "# RescueX 完整状态导出 - $RX_VERSION"
        echo "# 导出时间: $(get_log_time)"
        echo ""
        echo "=== 配置 ==="
        [ -f "$CONF_FILE" ] && cat "$CONF_FILE"
        echo ""
        echo "=== 白名单 ==="
        [ -f "$WHITELIST_FILE" ] && cat "$WHITELIST_FILE"
        echo ""
        echo "=== 启动状态 ==="
        [ -f "$STATUS_FILE" ] && cat "$STATUS_FILE"
        echo ""
        echo "=== 补丁失败计数 ==="
        [ -f "$PATCH_FAIL_COUNT_FILE" ] && cat "$PATCH_FAIL_COUNT_FILE"
        echo ""
        echo "=== 救砖禁用列表 ==="
        [ -f "$RESCUED_DISABLED_LIST" ] && cat "$RESCUED_DISABLED_LIST" || echo "(无)"
        echo ""
        echo "=== 救砖审计 ==="
        [ -f "$STATE_DIR/rescue_audit.log" ] && tail -n 50 "$STATE_DIR/rescue_audit.log" || echo "(无)"
        echo ""
        echo "=== 已知良好模块列表 ==="
        [ -f "$GOOD_MODULES_FILE" ] && cat "$GOOD_MODULES_FILE" || echo "(无)"
        echo ""
        echo "=== 嫌疑模块日志 ==="
        [ -f "$SUSPECT_LOG" ] && cat "$SUSPECT_LOG" || echo "(无)"
        echo ""
        echo "=== 救砖级别 ==="
        [ -f "$RESCUE_LEVEL_FILE" ] && cat "$RESCUE_LEVEL_FILE" || echo "0"
    } > "$out_file" 2>/dev/null
    # SEC-006: 导出文件设 0644 权限（以免 MediaScanner 读不到）
    chmod 0644 "$out_file" 2>/dev/null
    echo "$out_file"
}

# ============================================================
# 启动模式检测（v2.5 新增）
# 识别 Recovery / Fastbootd / Charger 等非正常启动模式
# 这些模式不应被计入"启动失败"，避免救砖逻辑误触发
# 返回 0=正常启动模式  1=非正常启动模式（应跳过失败计数）
# ============================================================
detect_boot_mode() {
    # 检查 ro.bootmode 属性（不同厂商命名有差异）
    local mode=""
    mode=$(getprop ro.bootmode 2>/dev/null)
    [ -z "$mode" ] && mode=$(getprop ro.boot.mode 2>/dev/null)
    case "$mode" in
        recovery|recovery2) return 1 ;;
        fastboot|fastbootd) return 1 ;;
        charger) return 1 ;;
        meta|metamode) return 1 ;;
        safe) return 1 ;;
    esac

    # 检查 ro.bootmode 的等价属性
    if getprop ro.boot.bootmode 2>/dev/null | grep -qi "recovery\|fastboot\|charger"; then
        return 1
    fi

    # Recovery 标记文件存在时也跳过
    # v2.6.0 F-BUG-3 加固：
    #   - 显式区分空文件（也是 recovery 残留特征）与含非 OTA 命令的文件
    #   - 补充 ro.boot.bootreason 信号（部分厂商用此属性记录上次启动原因）
    #   - 旧实现仅在 grep 失败时 return 1，但若文件为空 grep 也会失败，
    #     行为正确但注释模糊；现显式列出条件便于审计
    if [ -f "/cache/recovery/command" ]; then
        if ! grep -q "update_package" "/cache/recovery/command" 2>/dev/null; then
            # 文件存在但不含 update_package 命令（含空文件），视为 recovery 残留
            return 1
        fi
    fi
    # 部分厂商（Qualcomm / MTK）通过 ro.boot.bootreason 记录启动原因
    local bootreason
    bootreason=$(getprop ro.boot.bootreason 2>/dev/null)
    case "$bootreason" in
        recovery|recovery2|fastboot|fastbootd|charger|charger_mode)
            return 1
            ;;
    esac

    # sys.boot_completed 在 post-fs-data 阶段为空，不能用于判定

    return 0
}

# ============================================================
# LSPosed 禁用检测（v2.5 新增，用于诊断报告）
# 检测 LSPosed 模块是否被禁用
# 输出：禁用状态字符串
# ============================================================
detect_lsposed_state() {
    # LSPosed 状态文件路径（多版本兼容）
    # v2.6.0 F-BUG-6 修复：注释与代码路径完全对齐
    #   - 旧版 LSPosed（< v1.3.0）：禁用标记可能落在以下两个路径之一
    #       /data/adb/lsposed/disable_config         （目录或文件）
    #       /data/adb/lsposed/disable_config/db      （db 子文件）
    #   - 新版 LSPosed（>= v1.3.0 / LSPosed-core 重构后）：
    #       /data/adb/lspd/disable                   （单文件标记）
    # 同时检查父路径与 db 子文件，任一存在即判定为 legacy 禁用状态
    if [ -e "/data/adb/lsposed/disable_config" ] || [ -e "/data/adb/lsposed/disable_config/db" ]; then
        echo "disabled (legacy)"
        return
    fi
    if [ -f "/data/adb/lspd/disable" ]; then
        echo "disabled"
        return
    fi
    if [ -d "/data/adb/lspd" ] || [ -d "/data/adb/lsposed" ]; then
        # 目录存在但无 disable 标记
        # 进一步检查 LSPosed manager 的状态
        if [ -f "/data/adb/lspd/config/manager.json" ]; then
            echo "enabled"
            return
        fi
        echo "enabled (unknown state)"
        return
    fi
    echo "not_installed"
}

# ============================================================
# 启动统计计算（v2.5 新增，供 WebUI 统计面板使用）
# 基于 boot_history 文件计算：
#   - 总启动次数
#   - 成功次数（result=SUCCESS）
#   - 救砖次数（result=RESCUED）
#   - 启动失败次数
#   - 成功率（百分比）
#   - 平均启动耗时（基于 BOOT_DURATION，仅成功启动计入）
# 输出格式：KEY=VALUE 多行
# ============================================================
compute_boot_stats() {
    local total=0 success=0 rescued=0 failed=0
    local total_duration=0 duration_count=0
    local last_rescue_time=0 last_success_time=0
    local history_last_rescue_time=0 status_last_rescue_time=0 status_rescued=0
    # v2.6.0: 移除未使用的 first_boot_time 变量
    # 累计启动耗时（来自 SERVICE 行）
    local sum_duration=0

    [ ! -f "$HISTORY_FILE" ] && {
        echo "TOTAL=0"
        echo "SUCCESS=0"
        echo "RESCUED=0"
        echo "FAILED=0"
        echo "SUCCESS_RATE=0"
        echo "AVG_DURATION=0"
        echo "LAST_RESCUE_TIME=0"
        echo "LAST_SUCCESS_TIME=0"
        return
    }

    # boot_history 包含两种行格式：
    #   [time] START | fail=N | ota=bool | result=BOOTING  ← 每次开机记录
    #   [time] SERVICE | duration=Ns | result=SUCCESS      ← 启动成功记录
    #   [time] RESCUE | ...                                ← 救砖记录（watchdog_trigger）
    # 统计：TOTAL=START 行数，SUCCESS=SERVICE 行数，RESCUED=状态文件救砖计数，
    # FAILED=TOTAL-SUCCESS-非正常关机数（粗略估算）
    #
    # v2.6.0 F-BUG-1 加固说明：
    #   原审计报告指出某历史版本曾用 `sed -n 's/.*duration=\([0-9]*\)s\?.*/\1/p'`
    #   提取耗时，其中 `\?` 是 GNU sed 专有扩展，toybox/busybox sed 不兼容，
    #   导致 AVG_DURATION 永远为 0。当前实现已改用 POSIX shell 参数展开：
    #       dur_val=${line#*duration=}      # 去掉前缀到 duration=
    #       dur_val=${dur_val%%[!0-9]*}     # 去掉第一个非数字字符之后的所有内容
    #   现追加 awk 兜底：若参数展开后 dur_val 仍为空但行中确实含 duration=，
    #   说明参数展开在该 toybox 版本上未按预期工作，此时用 awk 重新提取，
    #   保证任何环境下平均耗时统计都不会静默失效。
    local line result dur_val hist_ts rescue_from_history=0
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        # 检测行类型
        case "$line" in
            *"SERVICE "*|*"SERVICE|"*)
                success=$((success + 1))
                # 提取 duration=Ns，使用 POSIX shell 参数展开兼容 toybox/busybox
                dur_val=""
                case "$line" in
                    *duration=*)
                        dur_val=${line#*duration=}
                        dur_val=${dur_val%%[!0-9]*}
                        # v2.6.0 F-BUG-1 awk 兜底：参数展开异常时重新提取
                        if [ -z "$dur_val" ]; then
                            dur_val=$(echo "$line" | awk -F'duration=' '{split($2,a,/[^0-9]/); print a[1]}' 2>/dev/null)
                            case "$dur_val" in ''|*[!0-9]*) dur_val="" ;; esac
                        fi
                        ;;
                esac
                case "$dur_val" in
                    ''|*[!0-9]*) ;;
                    *)
                        if [ "$dur_val" -gt 0 ] && [ "$dur_val" -lt 3600 ]; then
                            sum_duration=$((sum_duration + dur_val))
                            duration_count=$((duration_count + 1))
                        fi
                        ;;
                esac
                ;;
            *"START "*|*"START|"*)
                total=$((total + 1))
                # v2.6.0: 移除死代码 first_boot_time（计算后从未被使用）
                ;;
            *"RESCUE "*|*"RESCUE|"*)
                rescue_from_history=$((rescue_from_history + 1))
                case "$line" in
                    \[*\]*)
                        hist_ts=${line#"["}
                        hist_ts=${hist_ts%%"]"*}
                        case "$hist_ts" in
                            ''|*[!0-9]*) ;;
                            *) history_last_rescue_time="$hist_ts" ;;
                        esac
                        ;;
                esac
                ;;
        esac
    done < "$HISTORY_FILE"

    # 从状态文件读取救砖次数与时间
    if [ -f "$STATUS_FILE" ]; then
        status_last_rescue_time=$(grep "^LAST_RESCUE_TIME=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
        case "$status_last_rescue_time" in ''|*[!0-9]*) status_last_rescue_time=0 ;; esac
        status_rescued=$(grep "^RESCUE_COUNT=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
        case "$status_rescued" in ''|*[!0-9]*) status_rescued=0 ;; esac
        # BOOT_END 作为最近成功时间
        last_success_time=$(grep "^BOOT_END=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
        case "$last_success_time" in ''|*[!0-9]*) last_success_time=0 ;; esac
    fi

    # v3.2.0: 统计口径统一为 boot_history 优先，状态文件仅作历史缺失时兜底。
    # 这样旧版本遗留的 RESCUE_COUNT 脏数据不会继续污染 WebUI 统计。
    if [ "$rescue_from_history" -gt 0 ]; then
        rescued=$rescue_from_history
        last_rescue_time=$history_last_rescue_time
    else
        rescued=$status_rescued
        last_rescue_time=$status_last_rescue_time
    fi

    # 启动失败次数按实际启动次数估算：总启动 - 成功启动
    failed=$((total - success))
    [ "$failed" -lt 0 ] && failed=0

    local success_rate=0 avg_duration=0
    if [ "$total" -gt 0 ]; then
        success_rate=$((success * 100 / total))
    fi
    if [ "$duration_count" -gt 0 ]; then
        avg_duration=$((sum_duration / duration_count))
    fi

    echo "TOTAL=$total"
    echo "SUCCESS=$success"
    echo "RESCUED=$rescued"
    echo "FAILED=$failed"
    echo "SUCCESS_RATE=$success_rate"
    echo "AVG_DURATION=$avg_duration"
    echo "LAST_RESCUE_TIME=$last_rescue_time"
    echo "LAST_SUCCESS_TIME=$last_success_time"
}

get_dashboard_snapshot() {
    local wd_pid wd_status wd_cmd

    if [ -f "$STATUS_FILE" ]; then
        cat "$STATUS_FILE"
    else
        cat << 'EOF'
BOOT_START=0
BOOT_END=0
SERVICE_STARTED=0
FAIL_COUNT=0
LAST_BOOT_RESULT=UNKNOWN
OTA_DETECTED=false
RESCUE_COUNT=0
LAST_RESCUE_TIME=0
BOOT_DURATION=0
UPTIME_START=0
UPTIME_END=0
PATCH_DETECTED=false
EOF
    fi

    echo "PATCH_FLAG=$(cat "$PATCH_FLAG_FILE" 2>/dev/null || echo 0)"
    echo "PATCH_FAIL_COUNT=$(cat "$PATCH_FAIL_COUNT_FILE" 2>/dev/null || echo 0)"

    wd_pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || echo 0)
    echo "WD_PID=$wd_pid"
    wd_status="nopid"
    if [ -n "$wd_pid" ] && echo "$wd_pid" | grep -qE '^[0-9]+$'; then
        if kill -0 "$wd_pid" 2>/dev/null; then
            wd_cmd=$(cat "/proc/$wd_pid/cmdline" 2>/dev/null | tr '\0' ' ')
            case "$wd_cmd" in
                *watchdog*|*rescue*) wd_status="alive_ours" ;;
                *) wd_status="alive_other" ;;
            esac
        else
            wd_status="dead"
        fi
    fi
    echo "WD_STATUS=$wd_status"

    compute_boot_stats
}

# ============================================================
# 诊断报告生成（Feature-4）
# 收集设备信息 + 模块状态 + 日志，输出纯文本
# ============================================================
generate_report() {
    local tmp_report
    tmp_report=$(mktemp 2>/dev/null) || tmp_report="$STATE_DIR/.report.tmp"
    {
        echo "=========================================="
        echo "  RescueX 诊断报告"
        echo "  版本: $RX_VERSION (code=$RX_VERSION_CODE)"
        echo "  生成时间: $(get_log_time)"
        echo "=========================================="
        echo ""

        echo "=== 设备信息 ==="
        echo "型号: $(getprop ro.product.model 2>/dev/null)"
        echo "品牌: $(getprop ro.product.brand 2>/dev/null)"
        echo "Android 版本: $(getprop ro.build.version.release 2>/dev/null) (API $(getprop ro.build.version.sdk 2>/dev/null))"
        echo "内核: $(uname -r 2>/dev/null)"
        echo "构建号: $(getprop ro.build.display.id 2>/dev/null)"
        echo ""

        echo "=== 管理器检测 ==="
        [ -d /data/adb/magisk ] && echo "Magisk: 是 (版本 $(getprop magisk.version 2>/dev/null || echo 未知))"
        [ -d /data/adb/ksu ] && echo "KernelSU: 是"
        [ -d /data/adb/ap ] && echo "APatch: 是"
        echo ""

        echo "=== 启动模式检测（v2.5） ==="
        local boot_mode
        boot_mode=$(getprop ro.bootmode 2>/dev/null)
        [ -z "$boot_mode" ] && boot_mode=$(getprop ro.boot.mode 2>/dev/null)
        echo "ro.bootmode: ${boot_mode:-未知}"
        if getprop ro.boot.bootmode 2>/dev/null | grep -qi "recovery"; then
            echo "  → 检测到 Recovery 模式"
        elif getprop ro.boot.bootmode 2>/dev/null | grep -qi "fastboot"; then
            echo "  → 检测到 Fastboot/Fastbootd 模式"
        elif getprop ro.boot.bootmode 2>/dev/null | grep -qi "charger"; then
            echo "  → 检测到 Charger 模式"
        else
            echo "  → 正常启动模式"
        fi
        echo ""

        echo "=== LSPosed 状态（v2.5） ==="
        local lsposed_state
        lsposed_state=$(detect_lsposed_state)
        echo "LSPosed: $lsposed_state"
        echo ""

        echo "=== 启动统计（v2.5） ==="
        compute_boot_stats | while IFS='=' read -r k v; do
            [ -z "$k" ] && continue
            case "$k" in
                TOTAL) echo "  总启动次数: $v" ;;
                SUCCESS) echo "  成功次数: $v" ;;
                RESCUED) echo "  救砖次数: $v" ;;
                FAILED) echo "  失败次数: $v" ;;
                SUCCESS_RATE) echo "  成功率: ${v}%" ;;
                AVG_DURATION) echo "  平均启动耗时: ${v}s" ;;
                LAST_RESCUE_TIME)
                    if [ "$v" != "0" ]; then
                        echo "  最近救砖时间: $(date -d "@$v" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$v")"
                    else
                        echo "  最近救砖时间: 无"
                    fi
                    ;;
            esac
        done
        echo ""

        echo "=== RescueX 配置 ==="
        [ -f "$CONF_FILE" ] && cat "$CONF_FILE" || echo "(配置文件不存在)"
        echo ""

        echo "=== 白名单 ==="
        [ -f "$WHITELIST_FILE" ] && cat "$WHITELIST_FILE" || echo "(白名单为空)"
        echo ""

        echo "=== 当前启动状态 ==="
        [ -f "$STATUS_FILE" ] && cat "$STATUS_FILE" || echo "(状态文件不存在)"
        echo ""

        echo "=== 救砖历史 (最近 20 条) ==="
        # v2.6.0: get_log_time 现输出 epoch（无空格），此处转换为可读时间显示
        if [ -f "$HISTORY_FILE" ]; then
            tail -n 20 "$HISTORY_FILE" | while IFS= read -r hist_line; do
                # 提取 [time] 中的 epoch 并转换为人类可读时间
                # 注：此处位于 pipeline 子 shell，变量天然隔离，无需 local
                # 注：参数展开 ${var#"["} 用引号包裹字面字符，避免 \\[ 转义在某些 shell 不兼容
                case "$hist_line" in
                    \[*\]*)
                        ts_part=${hist_line#"["}
                        ts_part=${ts_part%%"]"*}
                        rest_part=${hist_line#"["*"]"}
                        # 仅当 ts_part 是纯数字（epoch）时转换
                        case "$ts_part" in
                            ''|*[!0-9]*)
                                echo "$hist_line"
                                ;;
                            *)
                                human_ts=$(date -d "@$ts_part" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "@$ts_part")
                                echo "[$human_ts]$rest_part"
                                ;;
                        esac
                        ;;
                    *)
                        echo "$hist_line"
                        ;;
                esac
            done
        else
            echo "(无历史)"
        fi
        echo ""

        echo "=== 救砖日志 (最近 30 条) ==="
        # v2.6.0: rescue.log 中时间戳同样为 epoch，做相同转换
        if [ -f "$LOG_FILE" ]; then
            tail -n 30 "$LOG_FILE" | while IFS= read -r log_line; do
                case "$log_line" in
                    \[*\]*)
                        lts_part=${log_line#"["}
                        lts_part=${lts_part%%"]"*}
                        lrest_part=${log_line#"["*"]"}
                        case "$lts_part" in
                            ''|*[!0-9]*)
                                # uptime+Ns 格式或其他，原样输出
                                echo "$log_line"
                                ;;
                            *)
                                lhuman_ts=$(date -d "@$lts_part" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "@$lts_part")
                                echo "[$lhuman_ts]$lrest_part"
                                ;;
                        esac
                        ;;
                    *)
                        echo "$log_line"
                        ;;
                esac
            done
        else
            echo "(无日志)"
        fi
        echo ""

        echo "=== 已安装模块列表 ==="
        list_all_modules | while IFS='|' read -r mid ena mgr; do
            echo "  [$mgr] $mid ($([ "$ena" = "1" ] && echo 启用 || echo 禁用))"
        done
        echo ""

        echo "=== 当前被禁用的模块 ==="
        local disabled
        disabled=$(list_disabled_modules)
        if [ -n "$disabled" ]; then
            echo "$disabled" | while read -r m; do echo "  - $m"; done
        else
            echo "  (无)"
        fi
        echo ""

        echo "=== 手动快照列表 ==="
        local snaps
        snaps=$(list_snapshots)
        if [ -n "$snaps" ]; then
            echo "$snaps" | while read -r s; do echo "  - $(basename "$s")"; done
        else
            echo "  (无)"
        fi

        echo ""
        echo "=== 自动快照 ==="
        normalize_snapshot_storage
        if [ -f "$AUTO_SNAPSHOT_FILE" ]; then
            echo "  - $(basename "$AUTO_SNAPSHOT_FILE")"
        else
            echo "  (无)"
        fi

        echo ""
        echo "=========================================="
        echo "  报告结束"
        echo "=========================================="
    } > "$tmp_report" 2>/dev/null
    cat "$tmp_report"
    rm -f "$tmp_report"
}

# ============================================================
# v3.0.0: 脚本目录禁用
# 在救砖时锁定所有脚本目录的脚本权限，防止 service.d 等目录中的
# 第三方脚本在救砖模式下的"最后一口气"执行导致问题
# 覆盖 Magisk / KernelSU / APatch 的所有脚本目录
# ============================================================
disable_script_dirs() {
    log "锁定脚本目录权限，防止救砖期间执行"
    local locked=0

    # Magisk / KSU / APatch 共有的脚本目录
    for dir in /data/adb/service.d /data/adb/post-fs-data.d; do
        if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
            chmod 000 "$dir"/* 2>/dev/null && locked=$((locked + 1))
            log "已锁定: $dir"
        fi
    done

    # KernelSU / APatch 额外支持的目录
    for dir in /data/adb/post-mount.d /data/adb/boot-completed.d; do
        if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
            chmod 000 "$dir"/* 2>/dev/null && locked=$((locked + 1))
            log "已锁定: $dir"
        fi
    done

    # 兼容旧版 KSU 路径
    [ -d "/data/adb/ksu/service.d" ] && chmod 000 /data/adb/ksu/service.d/* 2>/dev/null
    [ -d "/data/adb/ap/service.d" ] && chmod 000 /data/adb/ap/service.d/* 2>/dev/null

    log "脚本目录锁定完成 ($locked 个目录)"
    log_rescue_action "LOCK_SCRIPT_DIRS" "locked=$locked"
    SCRIPT_DIRS_LOCKED_LAST="$locked"
}

# ============================================================
# v3.0.0: 嫌疑模块追踪（Brick Guardian 核心功能）
# 开机成功后记录当前启用的模块列表（"已知良好"清单）
# 救砖时对比当前模块与已知良好清单，精准定位新安装/新启用的模块
# ============================================================

# 保存当前所有已安装模块列表为"已知正常"
# 由 service.sh 在每次成功启动后调用
# v3.0.0 BUG FIX: 保存 ALL 模块（含已禁用的），而非仅已启用的
# 原逻辑只保存启用模块，导致之前被禁用的模块（如 Surfing）不在列表中，
# 当其他模块（如测试模块）将其重新启用后，会被误判为"新出现的嫌疑模块"。
# 修复后保存所有模块，用冒号前缀标记禁用状态：
#   "modname" = 已启用
#   ":modname" = 已禁用
save_good_modules() {
    log "保存已知良好模块列表..."
    local count=0
    local tmp_list="${GOOD_MODULES_FILE}.tmp"
    rm -f "$tmp_list"

    local base mod_id mod_dir
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -z "$base" ] || [ ! -d "$base" ] && continue
        for mod_dir in "$base"/*/; do
            [ ! -d "$mod_dir" ] && continue
            mod_id=$(basename "$mod_dir")
            [ "$mod_id" = "$SELF_ID" ] && continue
            [ -f "${mod_dir}remove" ] && continue
            case "$mod_id" in *[!A-Za-z0-9._-]*) continue ;; esac
            # v3.0.0 FIX: 保存所有模块，用冒号前缀标记禁用状态
            if [ -f "${mod_dir}disable" ]; then
                echo ":${mod_id}" >> "$tmp_list"
            else
                echo "$mod_id" >> "$tmp_list"
            fi
            count=$((count + 1))
        done
    done

    if [ -f "$tmp_list" ]; then
        mv -f "$tmp_list" "$GOOD_MODULES_FILE"
        chmod 0600 "$GOOD_MODULES_FILE" 2>/dev/null
        log "已保存 $count 个已知良好模块"
    else
        # 没有任何模块，写空文件（表示初始状态）
        : > "$GOOD_MODULES_FILE"
        chmod 0600 "$GOOD_MODULES_FILE" 2>/dev/null
        log "已知良好模块列表为空（初始状态）"
    fi

    # v3.0.0: 启动成功后重置救砖级别为 0（下次救砖从嫌疑禁用开始）
    echo "0" > "$RESCUE_LEVEL_FILE" 2>/dev/null
    chmod 0600 "$RESCUE_LEVEL_FILE" 2>/dev/null
    prune_suspect_log
}

# 检测嫌疑模块：对比当前模块与已知良好列表
# 新安装的模块被标记为"确定嫌疑"，状态变化（禁用→启用）的模块被标记为"状态变化嫌疑"
# 返回 0=有明确嫌疑人, 1=无法定位（首次使用或全部已知）
# v3.0.0 BUG FIX: 适配新格式（含冒号前缀的禁用标记），同时检测状态变化
detect_suspect_modules() {
    log "开始检测嫌疑模块..."

    rm -f "$SUSPECT_LOG"

    # 没有已知良好列表 → 无法对比
    if [ ! -f "$GOOD_MODULES_FILE" ]; then
        log "无已知良好模块列表（首次使用），无法精准定位"
        echo "# 首次使用，无历史列表" > "$SUSPECT_LOG"
        return 1
    fi

    # 构建良好列表查找表：modname → "enabled" 或 "disabled"
    local good_table="/tmp/.rx_good_table.$$"
    rm -f "$good_table"
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
            :*) echo "${line#:}=disabled" >> "$good_table" ;;
            *) echo "${line}=enabled" >> "$good_table" ;;
        esac
    done < "$GOOD_MODULES_FILE"

    # 统计当前所有已安装模块并对比
    local suspect_count=0 state_change_count=0
    local base mod_id mod_dir
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -z "$base" ] || [ ! -d "$base" ] && continue
        for mod_dir in "$base"/*/; do
            [ ! -d "$mod_dir" ] && continue
            mod_id=$(basename "$mod_dir")
            [ "$mod_id" = "$SELF_ID" ] && continue
            [ -f "${mod_dir}remove" ] && continue
            case "$mod_id" in *[!A-Za-z0-9._-]*) continue ;; esac

            local current_state="enabled"
            [ -f "${mod_dir}disable" ] && current_state="disabled"

            # 查找在良好列表中的状态
            local prev_state=""
            if [ -f "$good_table" ]; then
                prev_state=$(grep "^${mod_id}=" "$good_table" 2>/dev/null | head -1 | cut -d= -f2)
            fi

            if [ -z "$prev_state" ]; then
                # 全新安装的模块（不在良好列表中）→ 确定嫌疑
                echo "$mod_id" >> "$SUSPECT_LOG"
                log "嫌疑模块（全新安装）: $mod_id"
                suspect_count=$((suspect_count + 1))
            elif [ "$prev_state" = "disabled" ] && [ "$current_state" = "enabled" ]; then
                # 之前禁用现在启用的模块 → 状态变化嫌疑（用 + 前缀标记）
                echo "+${mod_id}" >> "$SUSPECT_LOG"
                log "嫌疑模块（状态变化：禁用→启用）: $mod_id"
                state_change_count=$((state_change_count + 1))
            fi
            # 之前启用现在仍启用 → 不是嫌疑（已知良好且状态未变）
            # 之前启用现在禁用 → 不可能造成启动失败（它没在运行）
            # 之前禁用现在仍禁用 → 不可能造成启动失败
        done
    done
    rm -f "$good_table"

    local total_suspect=$((suspect_count + state_change_count))
    if [ "$total_suspect" -eq 0 ]; then
        log "未发现新模块或状态变化，可能是已知模块更新导致启动失败"
        # 将所有非自身启用模块标记为参考（? 前缀表示"不确定的嫌疑人"）
        for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
            [ -z "$base" ] || [ ! -d "$base" ] && continue
            for mod_dir in "$base"/*/; do
                [ ! -d "$mod_dir" ] && continue
                [ -f "${mod_dir}disable" ] && continue
                mod_id=$(basename "$mod_dir")
                [ "$mod_id" = "$SELF_ID" ] && continue
                case "$mod_id" in *[!A-Za-z0-9._-]*) continue ;; esac
                echo "?$mod_id" >> "$SUSPECT_LOG" 2>/dev/null
            done
        done
        log "无明确嫌疑人，已列出所有模块为参考"
        return 1
    fi

    log "共检测到 $suspect_count 个新安装嫌疑 + $state_change_count 个状态变化嫌疑"
    # 有确定嫌疑时返回 0
    [ "$suspect_count" -gt 0 ] && return 0
    # 仅有状态变化嫌疑时也返回 0（但这些优先级低于新安装嫌疑）
    return 0
}

# ============================================================
# v3.0.0: 三级渐进式救砖
# 级别 0: 嫌疑禁用 - 只禁用新出现的新安装/新启用模块（精准击中）
# 级别 1: 全量救砖 + 脚本目录锁定 - 禁用所有非白名单模块并锁定脚本目录
# 级别 2: APP 解冻 - 删除 package-restrictions.xml 解冻被冻结的应用
# ============================================================

# 读取当前救砖级别（0/1/2）
read_rescue_level() {
    RESCUE_LEVEL=0
    if [ -f "$RESCUE_LEVEL_FILE" ]; then
        local lv
        lv=$(cat "$RESCUE_LEVEL_FILE" 2>/dev/null | tr -d ' \t\r\n')
        case "$lv" in
            0|1|2) RESCUE_LEVEL=$lv ;;
            *) RESCUE_LEVEL=0 ;;
        esac
    fi
}

# 写入当前救砖级别
write_rescue_level() {
    echo "$1" > "$RESCUE_LEVEL_FILE" 2>/dev/null
    chmod 0600 "$RESCUE_LEVEL_FILE" 2>/dev/null
}

# 级别 0: 精准嫌疑禁用（禁用 detect_suspect_modules 发现的模块）
# v3.0.1 BUG FIX: 修复三个导致嫌疑模块未被实际禁用的 Bug：
#   1. 目录查找使用 $suspect（含 + 前缀）而非 $mod_id → +Surfing 查找 /modules/+Surfing 不存在
#   2. found 路径缺少末尾 / → disable_module_safe 创建 /modules/ModNamedisable 而非 /modules/ModName/disable
#   3. disable_module_safe 参数使用 $suspect 而非 $mod_id → mod_id 校验失败
# 同时改进：不确定嫌疑人（?前缀）也执行禁用，而非跳过
suspect_rescue() {
    log "===== 级别 0: 精准嫌疑禁用 ====="
    read_whitelist

    # v3.0.0: 救砖前自动拍快照
    local auto_snap
    auto_snap=$(take_snapshot auto)
    [ -n "$auto_snap" ] && log "救砖前自动快照: $(basename "$auto_snap")"

    if ! detect_suspect_modules; then
        log "无法精准定位嫌疑模块（首次使用或无新模块），升级到级别 1"
        write_rescue_level 1
        return 1
    fi

    # 读取嫌疑列表，同时处理确定嫌疑、状态变化嫌疑和不确定嫌疑人
    local disabled=0
    local suspect mod_id mod_dir found
    while IFS= read -r suspect || [ -n "$suspect" ]; do
        [ -z "$suspect" ] && continue
        # v3.0.1 FIX: ? 前缀（不确定嫌疑人）也要禁用，不再跳过
        # 只跳过注释行（# 开头）
        case "$suspect" in
            \#*) continue ;;  # 跳过注释
        esac
        # v3.0.1 FIX: 统一提取 mod_id，使用 $mod_id（而非 $suspect）进行目录查找和禁用
        case "$suspect" in
            \?*) mod_id="${suspect#\?}" ; log "  不确定嫌疑（仍将禁用）: $mod_id" ;;  # 不确定但需禁用
            +*) mod_id="${suspect#+}" ;;   # 状态变化嫌疑（禁用→启用）
            *) mod_id="$suspect" ;;         # 确定嫌疑（新安装）
        esac
        case "$mod_id" in *[!A-Za-z0-9._-]*) continue ;; esac
        [ "$mod_id" = "$SELF_ID" ] && continue
        is_whitelisted "$mod_id" && { log "  跳过白名单嫌疑: $mod_id"; continue; }

        # v3.0.1 FIX: 使用 $mod_id 查找目录，添加末尾 / 确保 disable 文件路径正确
        found=""
        for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
            [ -z "$base" ] || [ ! -d "$base" ] && continue
            if [ -d "$base/$mod_id" ]; then
                found="$base/$mod_id/"
                break
            fi
        done
        [ -z "$found" ] && { log "  嫌疑模块目录未找到: $mod_id"; continue; }

        # v3.0.1 FIX: 传 $mod_id（而非 $suspect）给 disable_module_safe
        if disable_module_safe "$found" "$mod_id"; then
            disabled=$((disabled + 1))
            log "  已禁用嫌疑模块: $mod_id"
        else
            log "  禁用嫌疑模块失败: $mod_id"
        fi
    done < "$SUSPECT_LOG"

    log "精准嫌疑禁用完成: 禁用 $disabled 个嫌疑模块"
    log_rescue_action "SUSPECT_RESCUE" "disabled=$disabled"

    # v3.0.1 FIX: 如果没有任何模块被禁用，视为嫌疑禁用失败，升级到级别 1
    if [ "$disabled" -eq 0 ]; then
        log "嫌疑禁用未能禁用任何模块，升级到全量救砖"
        write_rescue_level 1
        return 1
    fi

    # 升级救砖级别（下次启动若仍失败会执行级别 1）
    write_rescue_level 1
    return 0
}

# 级别 1: 全量救砖 + 脚本目录锁定
full_rescue_with_scripts() {
    log "===== 级别 1: 全量救砖 + 脚本目录锁定 ====="

    # 先执行常规全量救砖
    full_rescue

    # 锁定所有脚本目录
    disable_script_dirs

    log_rescue_action "FULL_RESCUE_SCRIPTS" "all_modules_and_scripts_locked"
    log "全量+脚本救砖完成"

    # 升级救砖级别（下次启动若失败会执行级别 2）
    write_rescue_level 2
    return 0
}

# 级别 2: APP 解冻（最后手段）
# 删除 package-restrictions.xml，解冻被 PM 冻结的应用
# 某些模块可能冻结了关键系统应用导致无法启动
app_unfreeze() {
    log "===== 级别 2: APP 解冻 ====="

    local unfreeze_done=0

    # 主要目标：/data/system/users/0/package-restrictions.xml
    if [ -f "/data/system/users/0/package-restrictions.xml" ]; then
        if rm -f "/data/system/users/0/package-restrictions.xml" 2>/dev/null; then
            log "已删除 package-restrictions.xml（用户 0）"
            unfreeze_done=1
        else
            log "删除 package-restrictions.xml（用户 0）失败"
        fi
    fi

    # 多用户环境：尝试所有用户
    for user_dir in /data/system/users/*/; do
        [ ! -d "$user_dir" ] && continue
        local pkg_rest="${user_dir}package-restrictions.xml"
        if [ -f "$pkg_rest" ]; then
            if rm -f "$pkg_rest" 2>/dev/null; then
                log "已删除: $pkg_rest"
                unfreeze_done=1
            fi
        fi
    done

    # 额外清理：部分厂商/ROM 可能有其他限制文件
    if [ -f "/data/system/users/0/package-restrictions.xml.backup" ]; then
        rm -f "/data/system/users/0/package-restrictions.xml.backup" 2>/dev/null
        log "已删除备份限制文件"
    fi

    if [ "$unfreeze_done" = "1" ]; then
        log "APP 解冻完成，准备重启"
        log_rescue_action "APP_UNFREEZE" "package-restrictions.xml deleted"
        sync
        APP_UNFREEZE_LAST_RESULT="DONE"
    else
        log "未发现需要解冻的限制文件"
        log_rescue_action "APP_UNFREEZE_SKIP" "no restrictions found"
        APP_UNFREEZE_LAST_RESULT="SKIP"
    fi

    # 重置救砖级别回到 0（解冻后若成功，下次从嫌疑禁用开始）
    write_rescue_level 0
    return 0
}

# 三级救砖编排器：根据当前救砖级别自动选择策略
# 在 post-fs-data.sh 和 watchdog_trigger 中调用
# v3.0.0 BUG FIX: 当嫌疑禁用无法精准定位时，立即升级到全量救砖
# 原逻辑：suspect_rescue 失败后只升级级别号，等下次启动再全量救砖
# 问题：看门狗已触发说明系统无法启动，不应再等一轮重启
# 修复：suspect_rescue 失败后立即执行 full_rescue_with_scripts
three_level_rescue() {
    read_rescue_level

    case "$RESCUE_LEVEL" in
        0)
            log "当前救砖级别: 0 → 尝试精准嫌疑禁用"
            if suspect_rescue; then
                log "精准嫌疑禁用成功"
            else
                log "嫌疑禁用未能精准定位嫌疑人，立即升级到全量救砖"
                full_rescue_with_scripts
            fi
            ;;
        1)
            log "当前救砖级别: 1 → 执行全量救砖 + 脚本目录锁定"
            full_rescue_with_scripts
            ;;
        2)
            log "当前救砖级别: 2 → 执行 APP 解冻（最后手段）"
            app_unfreeze
            ;;
        *)
            log "未知救砖级别 $RESCUE_LEVEL，回退到级别 1"
            write_rescue_level 1
            full_rescue_with_scripts
            ;;
    esac
}

# ============================================================
# 初始化
# ============================================================
_rescuex_init_paths
