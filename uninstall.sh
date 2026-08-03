#!/system/bin/sh
# RescueX v3.4.0 - uninstall.sh
# 兼容 Magisk / KernelSU / APatch 三套管理器
# 彻底清理看门狗进程和所有临时文件
#
# v3.0.1 改进：
# - 清理新增文件（good_modules.list, suspect_modules.log, rescue_level）

MODID="RescueX"

# 推断 MODDIR
MODDIR=""
for base in /data/adb/modules /data/adb/ksu/modules /data/adb/ap/modules /data/adb/ap_modules; do
    if [ -d "$base/$MODID" ]; then
        MODDIR="$base/$MODID"
        break
    fi
done
[ -z "$MODDIR" ] && MODDIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
[ -z "$MODDIR" ] && MODDIR="${0%/*}"

echo "RescueX 卸载中..."
echo "- 模块路径: $MODDIR"

STATE_DIR="$MODDIR/webroot/state"

# === 1. 安全停止看门狗 ===
if [ -f "$MODDIR/common.sh" ]; then
    . "$MODDIR/common.sh"
    stop_watchdog
    stop_integrity_daemon
    echo "- 看门狗和完整性守护已通过 common.sh 停止"
else
    if [ -f "$STATE_DIR/watchdog_pid" ]; then
        WD_PID=$(cat "$STATE_DIR/watchdog_pid" 2>/dev/null)
        case "$WD_PID" in
            ''|*[!0-9]*) ;;
            *)
                if kill -0 "$WD_PID" 2>/dev/null; then
                    WD_CMDLINE=$(cat /proc/$WD_PID/cmdline 2>/dev/null | tr '\0' ' ')
                    case "$WD_CMDLINE" in
                        *"${MODDIR}/watchdog.sh"*|*"${MODDIR}/watchdog"*)
                            kill "$WD_PID" 2>/dev/null
                            sleep 1
                            kill -9 "$WD_PID" 2>/dev/null
                            echo "- 看门狗已停止 (PID=$WD_PID)"
                            ;;
                    esac
                fi
                ;;
        esac
    fi
    if command -v pkill >/dev/null 2>&1 && pkill -f "${MODDIR}/watchdog.sh" 2>/dev/null; then
        :
    else
        for p in /proc/[0-9]*; do
            wp="${p#/proc/}"
            [ -f "$p/cmdline" ] || continue
            wc_line=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
            case "$wc_line" in
                *"${MODDIR}/watchdog.sh"*) kill -9 "$wp" 2>/dev/null ;;
            esac
        done
    fi
fi

# === 2. 彻底清理所有状态文件（含 v35 和 v3.5.1 新增）===
if [ -d "$STATE_DIR" ]; then
    # v3.5.1: 不再逐个列文件，直接递归删除整个 STATE_DIR，
    # 确保不遗漏任何新增的状态文件或子目录（v35/、health.d/、snapshot-meta/ 等）。
    rm -rf "$STATE_DIR"
    echo "- 状态数据已清理（含 v35 子目录）"
fi

# === 3. 彻底清理持久化目录 ===
# PERSIST_DIR 是跨更新保存状态的目录；如果不清，覆盖安装时
# customize.sh 会把旧状态恢复回来，导致旧 bug 无法通过更新消除。
if [ -d "/data/adb/rescuex_data" ]; then
    rm -rf "/data/adb/rescuex_data"
    echo "- 持久化数据已清理（/data/adb/rescuex_data）"
fi

# === 4. 清理其他临时位置 ===
rm -f "/data/local/tmp/$MODID/watchdog_pid" 2>/dev/null
rm -rf "/data/local/tmp/$MODID" 2>/dev/null

# === 5. 清理 module.prop.tmp 残留 ===
rm -f "$MODDIR/module.prop.tmp" 2>/dev/null

echo ""
echo "RescueX 已卸载完成"
echo ""
echo "提示："
echo "  1. 自动救砖功能已失效"
echo "  2. 若之前被救砖禁用了其他模块，请手动在管理器中重新启用"
echo "  3. 建议重启设备以彻底清理"
