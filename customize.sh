#!/system/bin/sh
# RescueX v3.4.0 - customize.sh

# v3.0.1 改进（专业级升级）：
# - 三级渐进式救砖支持
# - 嫌疑模块追踪基础设施初始化
# - APP 解冻功能

MODID="RescueX"
RX_VERSION="v3.5.3"

# 解析绝对路径（兼容 KSU/Magisk/APatch）
MODPATH="$(cd "${0%/*}" 2>/dev/null && pwd)"
[ -z "$MODPATH" ] && MODPATH="${0%/*}"

ui_print() { echo "$1"; }

get_manual_snapshot_limit() {
    local limit="${MAX_MANUAL_SNAPSHOTS:-12}"
    case "$limit" in ''|*[!0-9]*) limit=12 ;; esac
    [ "$limit" -lt 1 ] 2>/dev/null && limit=1
    echo "$limit"
}

prune_manual_snapshots_dir() {
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

# Compat-8: set_perm 兼容层
if ! command -v set_perm >/dev/null 2>&1; then
    set_perm() {
        local target="$1" owner="$2" group="$3" perm="$4"
        chmod "$perm" "$target" 2>/dev/null
        chown "${owner}:${group}" "$target" 2>/dev/null
    }
fi

ui_print "============================================"
ui_print "  RescueX 自动救砖 $RX_VERSION"
ui_print "  Reliable Bootloop Protection"
ui_print "============================================"

# === 系统版本检查 ===
API=$(getprop ro.build.version.sdk 2>/dev/null)
case "$API" in ''|*[!0-9]*) API=0 ;; esac
if [ "$API" -lt 28 ]; then
    ui_print "! 需要 Android 9.0 (API 28) 或更高版本"
    ui_print "! 当前 SDK: ${API:-未知}"
    exit 1
fi
ui_print "- 设备 SDK: $API"

MODEL=$(getprop ro.product.model 2>/dev/null | tr -cd 'A-Za-z0-9 ._-')
ui_print "- 设备型号: ${MODEL:-Unknown}"

# === 检测管理器类型 ===
MANAGER="unknown"
if [ -d "/data/adb/ksu" ]; then
    if pm list packages 2>/dev/null | grep -qi "sukisu"; then
        MANAGER="sukisuultra"
    else
        MANAGER="kernelsu"
    fi
elif [ -d "/data/adb/ap" ]; then
    MANAGER="apatch"
elif [ -d "/data/adb/magisk" ]; then
    MANAGER="magisk"
fi
ui_print "- 管理器: $MANAGER"

# === 创建状态目录 ===
STATE_DIR="$MODPATH/webroot/state"
SNAPSHOT_DIR="$STATE_DIR/snapshots"
PATCH_BACKUP_DIR="$STATE_DIR/patch_backup"
mkdir -p "$STATE_DIR" "$SNAPSHOT_DIR" "$PATCH_BACKUP_DIR"

# === 升级时保留旧版用户配置 ===
OLD_STATE_DIR=""
for old_base in /data/adb/modules /data/adb/ksu/modules /data/adb/ap/modules /data/adb/ap_modules; do
    if [ -d "$old_base/$MODID/webroot/state" ]; then
        OLD_STATE_DIR="$old_base/$MODID/webroot/state"
        break
    fi
done

# v2.7.0: 持久化目录（模块更新不丢失）
PERSIST_DIR="/data/adb/rescuex_data"
MAX_MANUAL_SNAPSHOTS=12
mkdir -p "$PERSIST_DIR" 2>/dev/null

CONFIG_PRESERVED=false
WHITELIST_PRESERVED=false
IS_UPGRADE=false

# v3.5.3: an old integrity daemon must be stopped before the module directory
# is replaced. Otherwise it can hash a half-updated tree and overwrite the new
# integrity status with a false COMPROMISED result.
stop_previous_integrity_daemon() {
    local pid_file pid cmdline waited
    for pid_file in "$OLD_STATE_DIR/integrity_pid" "$PERSIST_DIR/integrity_pid"; do
        [ -f "$pid_file" ] || continue
        pid=$(cat "$pid_file" 2>/dev/null)
        case "$pid" in ''|*[!0-9]*) continue ;; esac
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
        case "$cmdline" in
            *integrity.sh*)
                kill "$pid" 2>/dev/null || true
                waited=0
                while [ "$waited" -lt 5 ] && kill -0 "$pid" 2>/dev/null; do
                    sleep 1
                    waited=$((waited + 1))
                done
                kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
                ;;
        esac
    done
    [ -z "$OLD_STATE_DIR" ] || rm -f "$OLD_STATE_DIR/.integrity_start.lock" 2>/dev/null
    rm -f "$STATE_DIR/.integrity_start.lock" 2>/dev/null
}
if [ -n "$OLD_STATE_DIR" ] || [ -f "$PERSIST_DIR/integrity_pid" ]; then
    stop_previous_integrity_daemon
fi
# Mark every install/overlay as requiring one post-install baseline rebuild.
# This is intentionally outside the module directory so an overlay cannot
# preserve an old same-version manifest by accident.
printf 'VERSION_CODE=%s\n' "$(grep '^versionCode=' "$MODPATH/module.prop" 2>/dev/null | cut -d= -f2)" > "$PERSIST_DIR/integrity_upgrade_pending.tmp.$$"
chmod 0600 "$PERSIST_DIR/integrity_upgrade_pending.tmp.$$" 2>/dev/null
mv -f "$PERSIST_DIR/integrity_upgrade_pending.tmp.$$" "$PERSIST_DIR/integrity_upgrade_pending" 2>/dev/null || rm -f "$PERSIST_DIR/integrity_upgrade_pending.tmp.$$"

# v2.7.0: 优先从旧版模块目录迁移，其次从持久化目录恢复
if [ -n "$OLD_STATE_DIR" ]; then
    ui_print "- 检测到旧版安装，尝试保留用户配置"
    IS_UPGRADE=true
    # 配置
    if [ -f "$OLD_STATE_DIR/config.conf" ]; then
        cp "$OLD_STATE_DIR/config.conf" "$STATE_DIR/config.conf" 2>/dev/null && CONFIG_PRESERVED=true
    fi
    # 白名单
    if [ -f "$OLD_STATE_DIR/whitelist.conf" ]; then
        cp "$OLD_STATE_DIR/whitelist.conf" "$STATE_DIR/whitelist.conf" 2>/dev/null && WHITELIST_PRESERVED=true
    fi
    # 历史日志
    [ -f "$OLD_STATE_DIR/boot_history" ] && cp "$OLD_STATE_DIR/boot_history" "$STATE_DIR/boot_history" 2>/dev/null
    [ -f "$OLD_STATE_DIR/rescue.log" ] && cp "$OLD_STATE_DIR/rescue.log" "$STATE_DIR/rescue.log" 2>/dev/null
    # v2.7.0: 保留 boot_status（累计统计不丢失）
    if [ -f "$OLD_STATE_DIR/boot_status" ]; then
        cp "$OLD_STATE_DIR/boot_status" "$STATE_DIR/boot_status" 2>/dev/null
        ui_print "- 已保留启动统计数据"
    fi
    # v2.7.0: 保留补丁相关文件
    [ -f "$OLD_STATE_DIR/patch_fail_count" ] && cp "$OLD_STATE_DIR/patch_fail_count" "$STATE_DIR/patch_fail_count" 2>/dev/null
    [ -f "$OLD_STATE_DIR/patch_update_flag" ] && cp "$OLD_STATE_DIR/patch_update_flag" "$STATE_DIR/patch_update_flag" 2>/dev/null
    [ -f "$OLD_STATE_DIR/auto_snapshot_session" ] && cp "$OLD_STATE_DIR/auto_snapshot_session" "$STATE_DIR/auto_snapshot_session" 2>/dev/null
    # v2.7.0: 保留救砖审计日志
    [ -f "$OLD_STATE_DIR/rescue_audit.log" ] && cp "$OLD_STATE_DIR/rescue_audit.log" "$STATE_DIR/rescue_audit.log" 2>/dev/null
    [ -f "$OLD_STATE_DIR/onboarding_ack" ] && cp "$OLD_STATE_DIR/onboarding_ack" "$STATE_DIR/onboarding_ack" 2>/dev/null
    # 快照迁移
    if [ -d "$OLD_STATE_DIR/snapshots" ]; then
        snap_count=0
        for snap in "$OLD_STATE_DIR/snapshots"/snap-*.txt "$OLD_STATE_DIR/snapshots"/auto-snap-*.txt; do
            [ -f "$snap" ] || continue
            snap_name=$(basename "$snap")
            if [ ! -f "$SNAPSHOT_DIR/$snap_name" ]; then
                cp "$snap" "$SNAPSHOT_DIR/" 2>/dev/null && snap_count=$((snap_count + 1))
            fi
        done
        prune_manual_snapshots_dir "$SNAPSHOT_DIR"
        ui_print "- 已迁移 $snap_count 个快照"
    fi
fi

# v2.7.0: 如果旧版目录迁移失败，从持久化目录恢复
if [ "$CONFIG_PRESERVED" != "true" ] && [ -d "$PERSIST_DIR" ]; then
    ui_print "- 从持久化目录恢复数据"
    IS_UPGRADE=true
    [ -f "$PERSIST_DIR/config.conf" ] && cp "$PERSIST_DIR/config.conf" "$STATE_DIR/config.conf" 2>/dev/null && CONFIG_PRESERVED=true
    [ -f "$PERSIST_DIR/whitelist.conf" ] && cp "$PERSIST_DIR/whitelist.conf" "$STATE_DIR/whitelist.conf" 2>/dev/null && WHITELIST_PRESERVED=true
    [ -f "$PERSIST_DIR/boot_history" ] && cp "$PERSIST_DIR/boot_history" "$STATE_DIR/boot_history" 2>/dev/null
    [ -f "$PERSIST_DIR/boot_status" ] && cp "$PERSIST_DIR/boot_status" "$STATE_DIR/boot_status" 2>/dev/null && ui_print "- 已恢复启动统计"
    [ -f "$PERSIST_DIR/patch_fail_count" ] && cp "$PERSIST_DIR/patch_fail_count" "$STATE_DIR/patch_fail_count" 2>/dev/null
    [ -f "$PERSIST_DIR/auto_snapshot_session" ] && cp "$PERSIST_DIR/auto_snapshot_session" "$STATE_DIR/auto_snapshot_session" 2>/dev/null
    [ -f "$PERSIST_DIR/rescue_audit.log" ] && cp "$PERSIST_DIR/rescue_audit.log" "$STATE_DIR/rescue_audit.log" 2>/dev/null
    [ -f "$PERSIST_DIR/onboarding_ack" ] && cp "$PERSIST_DIR/onboarding_ack" "$STATE_DIR/onboarding_ack" 2>/dev/null
    [ -f "$PERSIST_DIR/good_modules.list" ] && cp "$PERSIST_DIR/good_modules.list" "$STATE_DIR/good_modules.list" 2>/dev/null
    if [ -d "$PERSIST_DIR/snapshots" ]; then
        for snap in "$PERSIST_DIR/snapshots"/snap-*.txt "$PERSIST_DIR/snapshots"/auto-snap-*.txt; do
            [ -f "$snap" ] || continue
            snap_name=$(basename "$snap")
            [ ! -f "$SNAPSHOT_DIR/$snap_name" ] && cp "$snap" "$SNAPSHOT_DIR/" 2>/dev/null
        done
        prune_manual_snapshots_dir "$SNAPSHOT_DIR"
    fi
fi

# === 写入默认配置（仅在未保留时）===
if [ "$CONFIG_PRESERVED" != "true" ]; then
    cat > "$STATE_DIR/config.conf" << 'CONF'
REBOOT_THRESHOLD=3
BOOT_TIMEOUT_SEC=90
OTA_TIMEOUT_SEC=900
ENABLED=true
LOG_ENABLED=true
DRY_RUN=true
PROGRESSIVE_RESCUE=true
AUTO_REENABLE=false
USER_REBOOT_GRACE_SEC=30
PATCH_UPDATE_TIMEOUT_SEC=180
PATCH_FAIL_THRESHOLD=2
PATCH_AUTO_ROLLBACK=true
WATCHDOG_POLL_INTERVAL_SEC=2
INTEGRITY_CHECK_ENABLED=true
INTEGRITY_INTERVAL_MIN_SEC=60
CONF
    ui_print "- 默认配置已写入"
else
    ui_print "- 已保留旧版配置"
    # 为旧版配置补全新增字段
    if ! grep -q "^PATCH_UPDATE_TIMEOUT_SEC=" "$STATE_DIR/config.conf" 2>/dev/null; then
        echo "PATCH_UPDATE_TIMEOUT_SEC=180" >> "$STATE_DIR/config.conf"
    fi
    if ! grep -q "^PATCH_FAIL_THRESHOLD=" "$STATE_DIR/config.conf" 2>/dev/null; then
        echo "PATCH_FAIL_THRESHOLD=2" >> "$STATE_DIR/config.conf"
    fi
    if ! grep -q "^PATCH_AUTO_ROLLBACK=" "$STATE_DIR/config.conf" 2>/dev/null; then
        echo "PATCH_AUTO_ROLLBACK=true" >> "$STATE_DIR/config.conf"
    fi
    if ! grep -q "^WATCHDOG_POLL_INTERVAL_SEC=" "$STATE_DIR/config.conf" 2>/dev/null; then
        echo "WATCHDOG_POLL_INTERVAL_SEC=2" >> "$STATE_DIR/config.conf"
    fi
    if ! grep -q "^INTEGRITY_CHECK_ENABLED=" "$STATE_DIR/config.conf" 2>/dev/null; then
        echo "INTEGRITY_CHECK_ENABLED=true" >> "$STATE_DIR/config.conf"
    fi
    if ! grep -q "^INTEGRITY_INTERVAL_MIN_SEC=" "$STATE_DIR/config.conf" 2>/dev/null; then
        echo "INTEGRITY_INTERVAL_MIN_SEC=60" >> "$STATE_DIR/config.conf"
    fi
    ui_print "- 已补全新增配置项"
fi

# === 写入白名单（仅在未保留时）===
if [ "$WHITELIST_PRESERVED" != "true" ]; then
    cat > "$STATE_DIR/whitelist.conf" << 'WL'
# 救砖时保留的模块（一行一个 ID，# 开头为注释）
# 只允许字母数字 . _ -
# 示例：
# font_module
# audio_mod
WL
    ui_print "- 默认白名单已写入"
else
    ui_print "- 已保留旧版白名单"
fi

# v2.7.0: boot_status 处理
# 升级时保留旧版 boot_status（含 RESCUE_COUNT 等累计数据）
# 首次安装时写入初始状态
if [ "$IS_UPGRADE" != "true" ] || [ ! -f "$STATE_DIR/boot_status" ]; then
    cat > "$STATE_DIR/boot_status" << 'STATUS'
BOOT_START=0
BOOT_END=0
SERVICE_STARTED=0
FAIL_COUNT=0
LAST_BOOT_RESULT=INIT
OTA_DETECTED=false
RESCUE_COUNT=0
LAST_RESCUE_TIME=0
BOOT_DURATION=0
UPTIME_START=0
UPTIME_END=0
PATCH_DETECTED=false
STATUS
fi

# === 初始化历史和日志（仅首次安装时清空，升级时一律保留）===
if [ "$IS_UPGRADE" != "true" ]; then
    : > "$STATE_DIR/boot_history"
    : > "$STATE_DIR/rescue.log"
fi
rm -f "$STATE_DIR/watchdog_pid"
rm -f "$STATE_DIR/.boot_status.tmp"
rm -f "$STATE_DIR/boot_status.json.tmp"
rm -f "$STATE_DIR/.boot_status.tmp."*
rm -f "$STATE_DIR/boot_status.json.tmp."*
rm -f "$STATE_DIR/.report.tmp"
# v2.7.0: 清理残留的救砖禁用列表（升级后可能已无效）
# 不清理 patch_update_flag 和 patch_fail_count（跨重启保留）

# === 完整性基线迁移 ===
# 核心脚本会随模块 ZIP 一起更新，旧版本 manifest 的哈希不能用于校验新版本。
# 仅清掉派生的完整性状态/基线；用户配置、白名单、快照、启动统计均保留。
if [ "$IS_UPGRADE" = "true" ]; then
    rm -f "$STATE_DIR/integrity.manifest" "$STATE_DIR/integrity_status" "$STATE_DIR/integrity_pid" 2>/dev/null
    rm -f "$PERSIST_DIR/integrity.manifest" 2>/dev/null
    ui_print "- 模块已更新：将在首次启动后建立新的完整性基线"
fi

# === 首次使用引导标记 ===
if [ "$IS_UPGRADE" != "true" ]; then
    echo "1" > "$STATE_DIR/first_run"
    ui_print "- 首次安装：已写入引导标记"
else
    if [ ! -f "$OLD_STATE_DIR/first_run" ] && [ ! -f "$PERSIST_DIR/first_run" ]; then
        echo "2" > "$STATE_DIR/first_run"
        ui_print "- 检测到从旧版升级：将显示新功能介绍"
    else
        # 保留旧版标记
        if [ -f "$OLD_STATE_DIR/first_run" ]; then
            cp "$OLD_STATE_DIR/first_run" "$STATE_DIR/first_run" 2>/dev/null
        elif [ -f "$PERSIST_DIR/first_run" ]; then
            cp "$PERSIST_DIR/first_run" "$STATE_DIR/first_run" 2>/dev/null
        fi
    fi
fi

# v2.7.0: 创建持久化目录并同步
mkdir -p "$PERSIST_DIR" 2>/dev/null
    for f in config.conf whitelist.conf boot_status boot_history patch_fail_count patch_update_flag first_run rescue_audit.log onboarding_ack good_modules.list rescue_level; do
    [ -f "$STATE_DIR/$f" ] && cp "$STATE_DIR/$f" "$PERSIST_DIR/$f" 2>/dev/null
done
if [ -d "$SNAPSHOT_DIR" ]; then
    mkdir -p "$PERSIST_DIR/snapshots" 2>/dev/null
    for snap in "$SNAPSHOT_DIR"/snap-*.txt "$SNAPSHOT_DIR"/auto-snap-*.txt; do
        [ -f "$snap" ] && cp "$snap" "$PERSIST_DIR/snapshots/" 2>/dev/null
    done
fi
chmod 0700 "$PERSIST_DIR" 2>/dev/null

# === 权限设置 ===
set_perm "$MODPATH" 0 0 0755
set_perm "$MODPATH/common.sh"        0 0 0700
set_perm "$MODPATH/post-fs-data.sh"  0 0 0700
set_perm "$MODPATH/service.sh"       0 0 0700
set_perm "$MODPATH/watchdog.sh"      0 0 0700
set_perm "$MODPATH/integrity.sh"     0 0 0700
set_perm "$MODPATH/uninstall.sh"     0 0 0700
set_perm "$MODPATH/action.sh"        0 0 0700
set_perm "$MODPATH/customize.sh"     0 0 0700
set_perm "$MODPATH/module.prop" 0 0 0644
# v3.5.3: remove the obsolete backup that could roll metadata back after an overlay update.
rm -f "$MODPATH/module.prop.bak" "$MODPATH/module.prop.tmp."* 2>/dev/null
set_perm "$MODPATH/README.md" 0 0 0644
set_perm "$MODPATH/LICENSE"  0 0 0644
set_perm "$MODPATH/webroot"           0 0 0755
set_perm "$MODPATH/webroot/arm64-v8a" 0 0 0755
set_perm "$MODPATH/webroot/assets"    0 0 0755
set_perm "$MODPATH/webroot/index.html" 0 0 0644
set_perm "$MODPATH/webroot/style.css"        0 0 0644
set_perm "$MODPATH/webroot/workspace-v2.css" 0 0 0644
set_perm "$MODPATH/webroot/script.js"         0 0 0644
set_perm "$STATE_DIR" 0 0 0700
set_perm "$SNAPSHOT_DIR" 0 0 0700
set_perm "$PATCH_BACKUP_DIR" 0 0 0700

# 状态文件权限
for f in config.conf whitelist.conf boot_status boot_history rescue.log onboarding_ack; do
    [ -f "$STATE_DIR/$f" ] && set_perm "$STATE_DIR/$f" 0 0 0600
done

ui_print "- 权限设置完成（最小权限原则）"
ui_print ""
ui_print "  默认参数："
ui_print "  · 连续重启阈值: 3 次"
ui_print "  · 开机超时: 90 秒"
ui_print "  · OTA 超时: 900 秒 (15 分钟)"
ui_print "  · 补丁超时: 180 秒"
ui_print "  · 渐进式救砖: 启用"
ui_print "  · 启动模式感知: 启用"
  ui_print "  · 数据持久化: 启用 (v3.4.0)"
ui_print "  · DRY_RUN: 关闭"
ui_print ""
ui_print "  通过 WebUI 可调整全部参数"
ui_print "  首次使用请在 WebUI 完成引导"
ui_print "  重启设备以生效"
ui_print "============================================"
