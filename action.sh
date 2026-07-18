#!/system/bin/sh
# RescueX v3.2.4 - Action 入口
# 兼容 KernelSU / KsuWebUI / MMRL / Magisk + APatch
#
# v3.0.1: WebUI 不可用时显示 CLI 状态信息（参考 BG 的 action.sh）

MODID="RescueX"

# 查找模块目录
for d in /data/adb/modules/$MODID /data/adb/modules_update/$MODID; do
    if [ -d "$d" ] && [ -f "$d/common.sh" ]; then
        MODDIR="$d"
        break
    fi
done

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

# === CLI 状态显示（WebUI 不可用时的回退） ===
show_cli_status() {
    echo "========================================="
    echo "   RescueX v3.2.4 - 模块状态"
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
        suspects=$(grep -v '^?' "$SUSPECT_FILE" 2>/dev/null | grep -v '^#' | grep -v '^unknown$' | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
        unclear=$(grep '^?' "$SUSPECT_FILE" 2>/dev/null | sed 's/^?//' | tr '\n' ',' | sed 's/,$//')
        if [ -n "$suspects" ]; then
            echo "嫌疑模块: $suspects"
        else
            echo "嫌疑模块: 无"
        fi
        if [ -n "$unclear" ]; then
            echo "参考模块: $unclear"
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
    elif [ "$APATCH" = "true" ]; then
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

# 尝试启动 WebUI
webui_launched=0

# 1. KsuWebUI
if is_pkg_installed "io.github.a13e300.ksuwebui"; then
    am start -n "io.github.a13e300.ksuwebui/.WebUIActivity" -e id "$MODID" 2>/dev/null
    [ $? -eq 0 ] && webui_launched=1
fi

# 2. MMRL WebUIX
if [ "$webui_launched" = "0" ] && is_pkg_installed "com.dergoogler.mmrl.wx"; then
    am start -n "com.dergoogler.mmrl.wx/.ui.activity.webui.WebUIActivity" -e MOD_ID "$MODID" 2>/dev/null
    [ $? -eq 0 ] && webui_launched=1
fi

# 3. MMRL 正式版
if [ "$webui_launched" = "0" ] && is_pkg_installed "com.dergoogler.mmrl"; then
    am start -n "com.dergoogler.mmrl/.ui.activity.webui.WebUIActivity" -e MOD_ID "$MODID" 2>/dev/null
    [ $? -eq 0 ] && webui_launched=1
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
