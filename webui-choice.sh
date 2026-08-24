#!/system/bin/sh
# RescueX WebUI installation preference helper.
# This file has no side effects when sourced. It only reads/writes the external
# preference record used by customize.sh and the WebUI.

RX_WEBUI_CHOICE_SCHEMA=1

rx_webui_choice_file() {
    printf '%s' "${RX_WEBUI_CHOICE_FILE:-${PERSIST_DIR:-/data/adb/rescuex_data}/webui_install_preference}"
}

rx_webui_choice_now() {
    local now
    now=$(date +%s 2>/dev/null)
    case "$now" in ''|*[!0-9]*) now=0 ;; esac
    printf '%s' "$now"
}

rx_webui_getprop() {
    command -v getprop >/dev/null 2>&1 || return 0
    getprop "$1" 2>/dev/null | tr -d '\r\n' | cut -c1-256
}

rx_webui_locale() {
    local value
    value=$(rx_webui_getprop persist.sys.locale)
    [ -n "$value" ] || value=$(rx_webui_getprop ro.product.locale)
    [ -n "$value" ] || value="${LC_ALL:-${LANG:-}}"
    printf '%s' "$value"
}

rx_webui_timezone() {
    local value
    value=$(rx_webui_getprop persist.sys.timezone)
    [ -n "$value" ] || value="${TZ:-UTC}"
    printf '%s' "$value"
}

# Language selection for installer output.
#
# v3.5.11: default to Chinese instead of English. The installer's static lines
# are Chinese, and recovery/installer environments frequently expose no readable
# locale (no getprop, or an empty persist.sys.locale), which previously made the
# volume-key prompt fall back to English while the surrounding device info stayed
# Chinese. Mixed-language output around a destructive-looking choice is worse
# than one consistent language, so only an explicitly non-Chinese locale selects
# English.
rx_webui_lang() {
    case "$(rx_webui_locale | tr '[:upper:]' '[:lower:]')" in
        '') printf 'zh' ;;
        zh*|cmn*|yue*|hak*|nan*) printf 'zh' ;;
        *) printf 'en' ;;
    esac
}

rx_webui_set_locale() {
    RX_WEBUI_LANG=$(rx_webui_lang)
    export RX_WEBUI_LANG
}

rx_webui_text() {
    local key="$1"
    [ -n "${RX_WEBUI_LANG:-}" ] || rx_webui_set_locale
    # The volume-key choice is the only irreversible-looking decision during
    # install, so those three lines are always bilingual regardless of locale.
    case "$key" in
        install) printf '[音量+] 安装 WebUI / Install WebUI'; return ;;
        skip) printf '[音量-] 暂不安装 WebUI / Skip WebUI'; return ;;
        timeout) printf '60 秒无操作将安装 WebUI / No input in 60s: install'; return ;;
    esac
    if [ "${RX_WEBUI_LANG:-zh}" = zh ]; then
        case "$key" in
            title) printf 'WebUI 安装选择' ;;
            supported) printf '当前管理器支持 WebUI' ;;
            unsupported) printf '当前管理器可能不支持原生 WebUI' ;;
            install) printf '[音量+] 安装 WebUI' ;;
            skip) printf '[音量-] 暂不安装 WebUI' ;;
            timeout) printf '60 秒无操作将安装 WebUI' ;;
            auto_install) printf '已按已确认偏好自动安装 WebUI' ;;
            auto_skip) printf '已按已确认偏好跳过 WebUI' ;;
            selected_install) printf '已选择：安装 WebUI' ;;
            selected_skip) printf '已选择：暂不安装 WebUI' ;;
            legacy_warning) printf '检测到已有 WebUI；本次音量下选择不会删除它，请在 WebUI 中确认最终偏好' ;;
            pref_path) printf '偏好路径：%s' "$(rx_webui_choice_file)" ;;
            locale) printf '系统语言：%s' "$(rx_webui_locale)" ;;
            timezone) printf '系统时区：%s' "$(rx_webui_timezone)" ;;
            *) printf '%s' "$key" ;;
        esac
    else
        case "$key" in
            title) printf 'WebUI installation choice' ;;
            supported) printf 'The current manager supports WebUI' ;;
            unsupported) printf 'The current manager may not provide native WebUI' ;;
            install) printf '[Volume Up] Install WebUI' ;;
            skip) printf '[Volume Down] Do not install WebUI for now' ;;
            timeout) printf 'No input for 60 seconds: WebUI will be installed' ;;
            auto_install) printf 'WebUI installed automatically from the confirmed preference' ;;
            auto_skip) printf 'WebUI skipped automatically from the confirmed preference' ;;
            selected_install) printf 'Selected: install WebUI' ;;
            selected_skip) printf 'Selected: do not install WebUI for now' ;;
            legacy_warning) printf 'An existing WebUI was found; Volume Down will not delete it this time. Confirm the final preference in WebUI.' ;;
            pref_path) printf 'Preference path: %s' "$(rx_webui_choice_file)" ;;
            locale) printf 'System locale: %s' "$(rx_webui_locale)" ;;
            timezone) printf 'System time zone: %s' "$(rx_webui_timezone)" ;;
            *) printf '%s' "$key" ;;
        esac
    fi
}

rx_webui_choice_read() {
    local key="$1" file
    case "$key" in
        SCHEMA|STATE|CHOICE|SOURCE|SET_AT|LOCALE|TIMEZONE) ;;
        *) return 1 ;;
    esac
    file=$(rx_webui_choice_file)
    [ -f "$file" ] || return 1
    sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -n 1
}

rx_webui_choice_is_valid() {
    local state choice schema
    schema=$(rx_webui_choice_read SCHEMA)
    state=$(rx_webui_choice_read STATE)
    choice=$(rx_webui_choice_read CHOICE)
    [ "$schema" = "$RX_WEBUI_CHOICE_SCHEMA" ] || return 1
    case "$state" in PENDING|DEFERRED|CONFIRMED) ;; *) return 1 ;; esac
    case "$choice" in install|skip) ;; *) return 1 ;; esac
    return 0
}

rx_webui_choice_is_confirmed() {
    rx_webui_choice_is_valid || return 1
    [ "$(rx_webui_choice_read STATE)" = CONFIRMED ]
}

rx_webui_choice_write_state() {
    local state="$1" choice="$2" source="$3" file tmp dir
    case "$state" in PENDING|DEFERRED|CONFIRMED) ;; *) return 1 ;; esac
    case "$choice" in install|skip) ;; *) return 1 ;; esac
    source=$(printf '%s' "$source" | tr -cd 'A-Za-z0-9._:-' | cut -c1-48)
    [ -n "$source" ] || source=unknown
    file=$(rx_webui_choice_file)
    dir=${file%/*}
    tmp="${file}.tmp.$$"
    umask 077
    mkdir -p "$dir" 2>/dev/null || return 1
    {
        printf 'SCHEMA=%s\n' "$RX_WEBUI_CHOICE_SCHEMA"
        printf 'STATE=%s\n' "$state"
        printf 'CHOICE=%s\n' "$choice"
        printf 'SOURCE=%s\n' "$source"
        printf 'SET_AT=%s\n' "$(rx_webui_choice_now)"
        printf 'LOCALE=%s\n' "$(rx_webui_locale | tr -cd 'A-Za-z0-9._@+-')"
        printf 'TIMEZONE=%s\n' "$(rx_webui_timezone | tr -cd 'A-Za-z0-9._+/-')"
    } > "$tmp" || { rm -f "$tmp" 2>/dev/null; return 1; }
    chmod 0600 "$tmp" 2>/dev/null
    sync "$tmp" 2>/dev/null
    mv -f "$tmp" "$file" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    chmod 0600 "$file" 2>/dev/null
    return 0
}

rx_webui_choice_write_pending() {
    rx_webui_choice_write_state PENDING "$1" "${2:-volume}"
}

rx_webui_choice_write_confirmed() {
    rx_webui_choice_write_state CONFIRMED "$1" "${2:-ui}"
}

rx_webui_choice_write_deferred() {
    rx_webui_choice_write_state DEFERRED "$1" "${2:-ui-defer}"
}

rx_webui_choice_status() {
    local state choice source pending confirmed
    state=$(rx_webui_choice_read STATE 2>/dev/null || printf 'NONE')
    choice=$(rx_webui_choice_read CHOICE 2>/dev/null || printf 'none')
    source=$(rx_webui_choice_read SOURCE 2>/dev/null || printf 'none')
    pending=false
    confirmed=false
    case "$state" in
        PENDING|DEFERRED) pending=true ;;
        CONFIRMED) confirmed=true ;;
    esac
    printf 'WEBUI_PREF_STATE=%s\n' "$state"
    printf 'WEBUI_PREF_CHOICE=%s\n' "$choice"
    printf 'WEBUI_PREF_SOURCE=%s\n' "$source"
    printf 'WEBUI_PREF_PENDING=%s\n' "$pending"
    printf 'WEBUI_PREF_CONFIRMED=%s\n' "$confirmed"
    printf 'WEBUI_PREF_LOCALE=%s\n' "$(rx_webui_choice_read LOCALE 2>/dev/null || printf '')"
    printf 'WEBUI_PREF_TIMEZONE=%s\n' "$(rx_webui_choice_read TIMEZONE 2>/dev/null || printf '')"
}
