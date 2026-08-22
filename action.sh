#!/system/bin/sh
# RescueX Action 入口（版本由 common.sh 的 RX_VERSION 统一定义）
# 兼容 KernelSU / KsuWebUI / MMRL / Magisk + APatch
#
# v3.0.1: WebUI 不可用时显示 CLI 状态信息（参考 BG 的 action.sh）

MODID="RescueX"

# 查找模块目录
for d in /data/adb/modules/$MODID /data/adb/modules_update/$MODID \
         /data/adb/ksu/modules/$MODID /data/adb/ksu/modules_update/$MODID \
         /data/adb/ap/modules/$MODID /data/adb/ap_modules/$MODID; do
    if [ -d "$d" ] && [ -f "$d/common.sh" ]; then
        MODDIR="$d"
        break
    fi
done

# 作为最后回退，允许从模块目录直接运行 action.sh（也便于离线诊断）。
if [ -z "$MODDIR" ]; then
    case "$0" in */*) action_parent=${0%/*} ;; *) action_parent=. ;; esac
    action_dir=$(CDPATH= cd -- "$action_parent" 2>/dev/null && pwd)
    [ -f "$action_dir/common.sh" ] && MODDIR="$action_dir"
fi

# CLI 必须在加载特性库前声明只读：features-v35.sh 会据此跳过目录创建与 chmod。
[ "${1:-}" = "--cli" ] && RESCUEX_READ_ONLY=true

# 尝试加载 common.sh 以复用函数
if [ -n "$MODDIR" ] && [ -f "$MODDIR/common.sh" ]; then
    # shellcheck disable=SC1090
    # 仅 source 路径初始化和日志函数（不执行可能触发 reboots 的逻辑）
    . "$MODDIR/common.sh"
    _rescuex_init_paths 2>/dev/null || true
fi

is_pkg_installed() {
    pm path "$1" > /dev/null 2>&1
}

is_foreground_pkg() {
    pkg="$1"
    dumpsys activity activities 2>/dev/null | grep -m1 'topResumedActivity' | grep -q "$pkg" && return 0
    dumpsys window windows 2>/dev/null | grep -m1 'mCurrentFocus' | grep -q "$pkg"
}

# === CLI 管理接口 ===
# Magisk 没有原生 WebUI；显式 --cli 命令让用户仍可安全地读取诊断数据。
# 所有当前命令均只读，不会修改模块、配置或救援状态。
show_cli_help() {
    cat <<'EOF'
RescueX CLI（只读）
用法: action.sh --cli <命令>

命令:
  status          显示模块与启动状态
  health          显示看门狗、完整性和目录健康状态
  timeline        显示最近结构化事件（最新在前）
  module-changes  显示相对稳定基线的模块变更与风险分数
  snapshots       显示快照名称、固定状态、时间和模块数
  safe-mode status 显示一次性安全模式事务状态
  simulate        预览当前失败计数下可能采取的救援动作
  rescue status   显示跨 Root 救砖事务状态（只读）
  rescue restore  恢复当前事务实际写入的 disable 标记（需 --apply）
  ota status      显示系统 OTA 检测状态（只读）
  ota arm         为下次系统更新启动设置 OTA 保护（需 --apply）
  ota clear       清除 OTA 手动保护（需 --apply）
  help            显示本帮助
EOF
}

run_cli_command() {
    command=${1:-help}
    case "$command" in
        help|-h|--help)
            show_cli_help
            ;;
        status)
            show_cli_status
            ;;
        health)
            v35_service_health
            ;;
        timeline)
            if [ -f "$V35_TIMELINE_FILE" ]; then v35_list_timeline; fi
            ;;
        module-changes)
            if [ -f "$V35_CHANGES_FILE" ]; then v35_list_module_changes; fi
            ;;
        snapshots)
            v35_list_snapshots_rich
            ;;
        safe-mode)
            [ "${2:-}" = status ] || { echo "用法: action.sh --cli safe-mode status" >&2; return 2; }
            v35_one_shot_status
            ;;
        rescue)
            case "${2:-status}" in
                status) rescue_transaction_status ;;
                restore)
                    [ "${3:-}" = "--apply" ] || { echo "用法: action.sh --cli rescue restore --apply" >&2; return 2; }
                    # Only this explicit subcommand may mutate state; override the
                    # default CLI read-only guard after user confirmation.
                    RESCUEX_READ_ONLY=false
                    rescue_transaction_restore_current
                    ;;
                *) echo "用法: action.sh --cli rescue status|restore --apply" >&2; return 2 ;;
            esac
            ;;
        ota)
            command -v ota_print_diagnostics >/dev/null 2>&1 || { echo "OTA 检测扩展不可用" >&2; return 1; }
            case "${2:-status}" in
                status) ota_print_diagnostics ;;
                arm)
                    [ "${3:-}" = "--apply" ] || { echo "用法: action.sh --cli ota arm --apply" >&2; return 2; }
                    RESCUEX_READ_ONLY=false
                    ota_set_manual_flag cli && echo "OTA 手动保护已设置"
                    ;;
                clear)
                    [ "${3:-}" = "--apply" ] || { echo "用法: action.sh --cli ota clear --apply" >&2; return 2; }
                    RESCUEX_READ_ONLY=false
                    ota_clear_manual_flag && echo "OTA 手动保护已清除"
                    ;;
                *) echo "用法: action.sh --cli ota status|arm --apply|clear --apply" >&2; return 2 ;;
            esac
            ;;
        simulate)
            # Fresh installs have no change file yet. Supply an empty read-only
            # stream so simulation can still emit a valid preview without writes.
            if [ ! -f "$V35_CHANGES_FILE" ]; then
                changes_file_backup=$V35_CHANGES_FILE
                V35_CHANGES_FILE=/dev/null
                v35_simulate_rescue
                rc=$?
                V35_CHANGES_FILE=$changes_file_backup
                # A missing change file is an expected fresh-install state.
                # Preserve failures from simulation itself instead of masking them.
                return "$rc"
            fi
            v35_simulate_rescue
            ;;
        *)
            echo "未知 CLI 命令: $command" >&2
            echo "运行 action.sh --cli help 查看可用命令。" >&2
            return 2
            ;;
    esac
}

# === CLI 状态显示（WebUI 不可用时的回退） ===
show_cli_status() {
    echo "========================================="
    echo "   RescueX ${RX_VERSION:-未知版本} - 模块状态"
    echo "========================================="
    echo ""

    # 模块启用状态
    if [ -d "/data/adb/modules/$MODID" ] && [ ! -f "/data/adb/modules/$MODID/disable" ]; then
        echo "状态:  已启用并运行中"
    elif [ -f "/data/adb/modules/$MODID/disable" ]; then
        echo "状态:  已禁用"
    else
        echo "状态:  未安装或异常"
    fi

    # 配置信息
    CONFIG_FILE="${STATE_DIR:-/data/adb/modules/$MODID/webroot/state}/config.conf"
    if [ -f "$CONFIG_FILE" ]; then
        threshold=$(grep "^REBOOT_THRESHOLD=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        timeout_s=$(grep "^BOOT_TIMEOUT_SEC=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        ota_timeout_s=$(grep "^OTA_TIMEOUT_SEC=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        dry=$(grep "^DRY_RUN=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        progressive=$(grep "^PROGRESSIVE_RESCUE=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        echo "重启阈值: ${threshold:-3} 次"
        echo "启动超时: ${timeout_s:-90} 秒"
        echo "OTA 超时: ${ota_timeout_s:-900} 秒"
        echo "DRY_RUN: ${dry:-false}"
        echo "渐进救砖: ${progressive:-true}"
    fi

    echo ""

    # 启动统计
    STATUS_FILE="${STATE_DIR:-/data/adb/modules/$MODID/webroot/state}/boot_status"
    if [ -f "$STATUS_FILE" ]; then
        rescue_count=$(grep "^RESCUE_COUNT=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
        fail_count=$(grep "^FAIL_COUNT=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
        last_result=$(grep "^LAST_BOOT_RESULT=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
        echo "已救砖: ${rescue_count:-0} 次"
        echo "当前失败: ${fail_count:-0} 次"
        echo "上次结果: ${last_result:-未知}"
    fi

    echo ""

    # 嫌疑模块
    SUSPECT_FILE="${STATE_DIR:-/data/adb/modules/$MODID/webroot/state}/suspect_modules.log"
    if [ -f "$SUSPECT_FILE" ]; then
        suspects=$(grep -v '^?' "$SUSPECT_FILE" 2>/dev/null | grep -v '^+' | grep -v '^#' | grep -v '^unknown$' | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
        changed=$(grep '^+' "$SUSPECT_FILE" 2>/dev/null | sed 's/^+//' | tr '\n' ',' | sed 's/,$//')
        unclear=$(grep '^?' "$SUSPECT_FILE" 2>/dev/null | sed 's/^?//' | tr '\n' ',' | sed 's/,$//')
        if [ -n "$suspects" ]; then
            echo "嫌疑模块: $suspects"
        else
            echo "嫌疑模块: 无"
        fi
        if [ -n "$unclear" ]; then
            echo "参考模块: $unclear"
        fi
        if [ -n "$changed" ]; then
            echo "状态变化嫌疑: $changed"
        fi
    fi

    # 救砖级别
    LEVEL_FILE="${STATE_DIR:-/data/adb/modules/$MODID/webroot/state}/rescue_level"
    if [ -f "$LEVEL_FILE" ]; then
        level=$(cat "$LEVEL_FILE" 2>/dev/null | tr -d ' \t\r\n')
        echo "救砖级别: ${level:-0}"
    fi

    echo ""

    # 已知良好模块（仅统计启用状态的，不含 ':' 前缀）
    GOOD_FILE="${STATE_DIR:-/data/adb/modules/$MODID/webroot/state}/good_modules.list"
    if [ -f "$GOOD_FILE" ]; then
        good_count=$(grep -cv '^:' "$GOOD_FILE" 2>/dev/null || echo 0)
        echo "已知良好模块: ${good_count:-0} 个"
    else
        echo "已知良好模块: 未建立"
    fi

    if command -v ota_print_diagnostics >/dev/null 2>&1; then
        echo ""
        echo "系统 OTA 检测:"
        ota_print_diagnostics
    fi

    echo ""
    echo "-----------------------------------------"
    echo "系统信息:"
    echo "Android: $(getprop ro.build.version.release) | SDK: $(getprop ro.build.version.sdk)"
    echo "设备: $(getprop ro.product.model)"
    echo "版本号: $(getprop ro.system.build.version.incremental)"

    # Root 管理器
    if [ "$KSU" = "true" ] || [ -d "/data/adb/ksu" ]; then
        if pm list packages 2>/dev/null | grep -qi "sukisu"; then
            echo "Root: SukiSU Ultra ${KSU_VER:-unknown}"
        else
            echo "Root: KernelSU ${KSU_VER:-unknown}"
        fi
    elif [ "$APATCH" = "true" ] || [ -d "/data/adb/ap" ] || [ -d "/data/adb/ap_modules" ]; then
        echo "Root: APatch ${APATCH_VER:-unknown}"
    elif [ -d "/data/adb/magisk" ]; then
        echo "Root: Magisk $(magisk -v 2>/dev/null || echo 'unknown')"
    else
        echo "Root: 未知"
    fi

    echo ""
    echo "========================================="
    echo "安装 KsuWebUI 或 MMRL 可使用图形管理界面"
    echo "KsuWebUI: https://github.com/tiann/KernelSU/releases"
    echo "MMRL:     https://github.com/dergoogler/MMRL/releases"
    echo ""
}

# 仅在明确请求时启用 CLI，避免破坏 Root 管理器原有 action 行为。
# 放在 show_cli_status 定义之后，使 status 子命令在 POSIX sh 中可用。
if [ "${1:-}" = "--cli" ]; then
    run_cli_command "${2:-help}" "${3:-}" "${4:-}"
    exit $?
fi

# 尝试启动 WebUI
webui_launched=0

# 1. KsuWebUI
if is_pkg_installed "io.github.a13e300.ksuwebui"; then
    am start -n "io.github.a13e300.ksuwebui/.WebUIActivity" -e id "$MODID" 2>/dev/null
    [ $? -eq 0 ] && webui_launched=1
fi

# 2. MMRL WebUIX
if [ "$webui_launched" = "0" ] && is_pkg_installed "com.dergoogler.mmrl.wx" && ! is_foreground_pkg "com.dergoogler.mmrl.wx"; then
    am start -n "com.dergoogler.mmrl.wx/.ui.activity.webui.WebUIActivity" -e MOD_ID "$MODID" 2>/dev/null
    [ $? -eq 0 ] && webui_launched=1
fi

# 3. MMRL 正式版
if [ "$webui_launched" = "0" ] && is_pkg_installed "com.dergoogler.mmrl" && ! is_foreground_pkg "com.dergoogler.mmrl"; then
    am start -n "com.dergoogler.mmrl/.ui.activity.webui.WebUIActivity" -e MOD_ID "$MODID" 2>/dev/null
    [ $? -eq 0 ] && webui_launched=1
fi

if [ "$webui_launched" = "0" ] && { is_foreground_pkg "com.dergoogler.mmrl" || is_foreground_pkg "com.dergoogler.mmrl.wx"; }; then
    echo "检测到当前已在 MMRL 内部，跳过二次拉起 WebUIActivity。"
    echo "请直接返回模块页面后重新进入 WebUI。"
    exit 0
fi

# 4. KernelSU 管理器原生
if [ "$webui_launched" = "0" ] && [ -d "/data/adb/ksu" ] && is_pkg_installed "me.weishu.kernelsu"; then
    for act in "me.weishu.kernelsu/.ui.WebUIActivity" "me.weishu.kernelsu/.WebUIActivity"; do
        am start -n "$act" -e id "$MODID" 2>/dev/null
        if [ $? -eq 0 ]; then
            webui_launched=1
            break
        fi
    done
fi

# 4.5 SukiSU Ultra 兼容：沿用 KSU 模块目录，优先尝试通用 deep link
if [ "$webui_launched" = "0" ] && [ -d "/data/adb/ksu" ] && pm list packages 2>/dev/null | grep -qi "sukisu"; then
    am start -a android.intent.action.VIEW -d "kernelsu://module/$MODID" 2>/dev/null
    [ $? -eq 0 ] && webui_launched=1
fi

# 5. APatch
if [ "$webui_launched" = "0" ] && [ -d "/data/adb/ap" ] && is_pkg_installed "me.bmax.apatch"; then
    am start -n "me.bmax.apatch/.ui.WebUIActivity" -e id "$MODID" 2>/dev/null
    [ $? -eq 0 ] && webui_launched=1
fi

# 6. Magisk（无原生 WebUI）— 显示 CLI 状态
if [ "$webui_launched" = "0" ] && [ -d "/data/adb/magisk" ]; then
    show_cli_status
    exit 0
fi

# 7. Deeplink fallback
if [ "$webui_launched" = "0" ]; then
    am start -a android.intent.action.VIEW -d "kernelsu://module/$MODID" 2>/dev/null
    if [ $? -eq 0 ]; then
        webui_launched=1
        exit 0
    fi
fi

# WebUI 已启动成功，显示简要提示
if [ "$webui_launched" = "1" ]; then
    echo "WebUI 已启动"
    exit 0
fi

# 所有尝试失败，显示 CLI 状态
show_cli_status
exit 1
