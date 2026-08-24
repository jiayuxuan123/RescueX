#!/system/bin/sh
# RescueX system OTA detection extension.
# This library only decides whether to use the longer OTA boot timeout. It does
# not increment failures, disable modules, restore state, or schedule reboots.

OTA_DETECTION_SCHEMA=1
OTA_BASELINE_FILE="${OTA_BASELINE_FILE:-${PERSIST_DIR:-/data/adb/rescuex_data}/ota_build_baseline}"
OTA_MANUAL_FLAG_FILE="${OTA_MANUAL_FLAG_FILE:-${PERSIST_DIR:-/data/adb/rescuex_data}/ota_update_pending}"
OTA_DETECTION_STATUS_FILE="${OTA_DETECTION_STATUS_FILE:-${STATE_DIR:-${MODDIR:-/data/adb/modules/RescueX}/webroot/state}/ota_detection_status}"
# OTA_PROBE_ROOT is empty on devices. Tests can point it at a fixture tree so
# vendor marker checks remain deterministic without touching /data.
OTA_PROBE_ROOT="${OTA_PROBE_ROOT:-}"
OTA_DETECTION_SOURCE=none
OTA_DETECTION_REASON=none
OTA_VENDOR_SIGNAL=false
OTA_VENDOR_REASON=none
OTA_BASELINE_READY=false

_ota_now_sec() {
    local now
    now=$(date +%s 2>/dev/null)
    case "$now" in ''|*[!0-9]*) now=0 ;; esac
    printf '%s' "$now"
}

_ota_getprop() {
    getprop "$1" 2>/dev/null | tr -d '\r\n' | cut -c1-512
}

_ota_probe_path() {
    local path="$1"
    if [ -n "$OTA_PROBE_ROOT" ]; then
        case "$path" in
            /*) printf '%s%s' "${OTA_PROBE_ROOT%/}" "$path" ;;
            *) printf '%s/%s' "${OTA_PROBE_ROOT%/}" "$path" ;;
        esac
    else
        printf '%s' "$path"
    fi
}

_ota_probe_file() {
    [ -f "$(_ota_probe_path "$1")" ]
}

_ota_probe_dir() {
    [ -d "$(_ota_probe_path "$1")" ]
}

_ota_probe_read() {
    local path
    path=$(_ota_probe_path "$1")
    [ -f "$path" ] || return 1
    tr -d '\r' < "$path" 2>/dev/null | head -n 1 | cut -c1-512
}

_ota_state_active() {
    local value lower
    value=$(printf '%s' "$1" | tr -d '\r\n' | cut -c1-512)
    lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        ''|0|false|none|unknown|idle|complete|completed|success|successful|failed|failure|error|cancel|cancelled|canceled|not_*|no_*)
            return 1
            ;;
    esac
    case "$lower" in
        *download*|*install*|*updat*|*verify*|*apply*|*reboot*|*pending*|*running*|*writing*|*prepar*|*switch*|ready|ready_to_update)
            return 0
            ;;
    esac
    return 1
}

_ota_recent_path() {
    local path="$1" now mtime age
    path=$(_ota_probe_path "$path")
    [ -e "$path" ] || return 1
    now=$(_ota_now_sec)
    mtime=$(stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null || echo 0)
    case "$now:$mtime" in *[!0-9:]*|*:0|0:*) return 1 ;; esac
    [ "$mtime" -le "$now" ] 2>/dev/null || return 1
    age=$((now - mtime))
    [ "$age" -lt 3600 ]
}

_ota_normalize_slot() {
    local slot
    slot=$(_ota_getprop ro.boot.slot_suffix)
    [ -n "$slot" ] || slot=$(_ota_getprop ro.boot.slot)
    slot=$(printf '%s' "$slot" | tr -d '_ ' | tr '[:upper:]' '[:lower:]')
    case "$slot" in a|b) printf '%s' "$slot" ;; *) printf '' ;; esac
}

_ota_read_key() {
    local key="$1" file="$2"
    sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -n 1
}

_ota_write_current_identity() {
    printf 'SCHEMA=%s\n' "$OTA_DETECTION_SCHEMA"
    printf 'CAPTURED_AT=%s\n' "$(_ota_now_sec)"
    printf 'BUILD_FINGERPRINT=%s\n' "$(_ota_getprop ro.build.fingerprint)"
    printf 'SYSTEM_FINGERPRINT=%s\n' "$(_ota_getprop ro.system.build.fingerprint)"
    printf 'VENDOR_FINGERPRINT=%s\n' "$(_ota_getprop ro.vendor.build.fingerprint)"
    printf 'PRODUCT_FINGERPRINT=%s\n' "$(_ota_getprop ro.product.build.fingerprint)"
    printf 'BOOTIMAGE_FINGERPRINT=%s\n' "$(_ota_getprop ro.bootimage.build.fingerprint)"
    printf 'INCREMENTAL=%s\n' "$(_ota_getprop ro.build.version.incremental)"
    printf 'SECURITY_PATCH=%s\n' "$(_ota_getprop ro.build.version.security_patch)"
    printf 'SDK=%s\n' "$(_ota_getprop ro.build.version.sdk)"
    printf 'RELEASE=%s\n' "$(_ota_getprop ro.build.version.release)"
    printf 'BUILD_ID=%s\n' "$(_ota_getprop ro.build.id)"
    printf 'SLOT=%s\n' "$(_ota_normalize_slot)"
    printf 'TIMEZONE=%s\n' "$(_ota_get_timezone)"
}

_ota_baseline_file_is_ready() {
    local file="${1:-$OTA_BASELINE_FILE}" schema fingerprint system_fp incremental build_id
    [ -f "$file" ] || return 1
    schema=$(_ota_read_key SCHEMA "$file")
    [ "$schema" = "$OTA_DETECTION_SCHEMA" ] || return 1
    fingerprint=$(_ota_read_key BUILD_FINGERPRINT "$file")
    system_fp=$(_ota_read_key SYSTEM_FINGERPRINT "$file")
    incremental=$(_ota_read_key INCREMENTAL "$file")
    build_id=$(_ota_read_key BUILD_ID "$file")
    [ -n "$fingerprint$system_fp$incremental$build_id" ]
}

ota_baseline_is_ready() {
    _ota_baseline_file_is_ready "$OTA_BASELINE_FILE"
}

_ota_atomic_write_stream() {
    local file="$1" tmp="${1}.tmp.$$"
    mkdir -p "${file%/*}" 2>/dev/null || return 1
    cat > "$tmp" || { rm -f "$tmp" 2>/dev/null; return 1; }
    chmod 0600 "$tmp" 2>/dev/null
    sync "$tmp" 2>/dev/null
    mv -f "$tmp" "$file" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    chmod 0600 "$file" 2>/dev/null
}

ota_commit_build_baseline() {
    local tmp="${OTA_BASELINE_FILE}.candidate.$$"
    mkdir -p "${OTA_BASELINE_FILE%/*}" 2>/dev/null || return 1
    _ota_write_current_identity > "$tmp" || { rm -f "$tmp" 2>/dev/null; return 1; }
    if ! _ota_baseline_file_is_ready "$tmp"; then
        rm -f "$tmp" 2>/dev/null
        return 1
    fi
    chmod 0600 "$tmp" 2>/dev/null
    sync "$tmp" 2>/dev/null
    mv -f "$tmp" "$OTA_BASELINE_FILE" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    chmod 0600 "$OTA_BASELINE_FILE" 2>/dev/null
    OTA_BASELINE_READY=true
    return 0
}

ota_initialize_baseline_if_missing() {
    ota_baseline_is_ready && { OTA_BASELINE_READY=true; return 0; }
    ota_commit_build_baseline
}

_ota_append_reason() {
    local reason="$1"
    case "$OTA_DETECTION_REASON" in
        ''|none) OTA_DETECTION_REASON="$reason" ;;
        *) OTA_DETECTION_REASON="${OTA_DETECTION_REASON},${reason}" ;;
    esac
}

_ota_compare_value() {
    local key="$1" current="$2" reason="$3" previous
    previous=$(_ota_read_key "$key" "$OTA_BASELINE_FILE")
    [ -n "$previous" ] && [ -n "$current" ] && [ "$previous" != "$current" ] || return 1
    _ota_append_reason "$reason"
    return 0
}

ota_detect_build_change() {
    local changed=0
    OTA_DETECTION_REASON=none
    if ! ota_baseline_is_ready; then
        OTA_BASELINE_READY=false
        return 1
    fi
    OTA_BASELINE_READY=true

    _ota_compare_value BUILD_FINGERPRINT "$(_ota_getprop ro.build.fingerprint)" build_fingerprint_changed && changed=1
    _ota_compare_value SYSTEM_FINGERPRINT "$(_ota_getprop ro.system.build.fingerprint)" system_fingerprint_changed && changed=1
    _ota_compare_value VENDOR_FINGERPRINT "$(_ota_getprop ro.vendor.build.fingerprint)" vendor_fingerprint_changed && changed=1
    _ota_compare_value PRODUCT_FINGERPRINT "$(_ota_getprop ro.product.build.fingerprint)" product_fingerprint_changed && changed=1
    _ota_compare_value BOOTIMAGE_FINGERPRINT "$(_ota_getprop ro.bootimage.build.fingerprint)" bootimage_fingerprint_changed && changed=1
    _ota_compare_value INCREMENTAL "$(_ota_getprop ro.build.version.incremental)" incremental_changed && changed=1
    _ota_compare_value SECURITY_PATCH "$(_ota_getprop ro.build.version.security_patch)" security_patch_changed && changed=1
    _ota_compare_value SDK "$(_ota_getprop ro.build.version.sdk)" sdk_changed && changed=1
    _ota_compare_value RELEASE "$(_ota_getprop ro.build.version.release)" release_changed && changed=1
    _ota_compare_value BUILD_ID "$(_ota_getprop ro.build.id)" build_id_changed && changed=1
    _ota_compare_value SLOT "$(_ota_normalize_slot)" slot_changed && changed=1

    [ "$changed" -eq 1 ]
}

ota_manual_flag_active() {
    [ -f "$OTA_MANUAL_FLAG_FILE" ] || return 1
    [ "$(_ota_read_key SCHEMA "$OTA_MANUAL_FLAG_FILE")" = "$OTA_DETECTION_SCHEMA" ] || return 1
    [ "$(_ota_read_key STATE "$OTA_MANUAL_FLAG_FILE")" = PENDING ]
}

ota_set_manual_flag() {
    local note
    note=$(printf '%s' "${1:-webui}" | tr -cd 'A-Za-z0-9._-' | cut -c1-48)
    {
        printf 'SCHEMA=%s\n' "$OTA_DETECTION_SCHEMA"
        printf 'STATE=PENDING\n'
        printf 'SET_AT=%s\n' "$(_ota_now_sec)"
        printf 'SOURCE=%s\n' "${note:-manual}"
    } | _ota_atomic_write_stream "$OTA_MANUAL_FLAG_FILE"
}

ota_clear_manual_flag() {
    rm -f "$OTA_MANUAL_FLAG_FILE" "${OTA_MANUAL_FLAG_FILE}.tmp."* 2>/dev/null
    return 0
}

_ota_get_timezone() {
    local tz
    tz=$(_ota_getprop persist.sys.timezone)
    [ -n "$tz" ] || tz=$(_ota_getprop ro.system.timezone)
    [ -n "$tz" ] || tz="${TZ:-UTC}"
    printf '%s' "$tz" | tr -cd 'A-Za-z0-9._+/-' | cut -c1-64
}

# Only volatile `sys.*` properties are trusted. `ro.*` and `persist.*` update
# state survive reboots, so a device that finished an update months ago would
# otherwise report an OTA on every single boot. A genuinely completed update is
# recognized by the build baseline instead.
_ota_vendor_state_property() {
    local key value
    for key in \
        sys.oplus.ota.state \
        sys.oplus.ota.update_state \
        sys.oplus.update.state \
        sys.oppo.update_state \
        sys.miui.update_state \
        sys.vivo.update_state \
        sys.ota.update_state \
        sys.update_engine.status; do
        value=$(_ota_getprop "$key")
        [ -n "$value" ] || continue
        _ota_state_active "$value" || continue
        OTA_VENDOR_REASON="property_${key}"
        return 0
    done
    return 1
}

# Vendor update signals are detection-only. This function never calls
# pm disable, mount, setprop, or cache cleanup, and it must not report an
# update just because an OTA daemon exists. On A/B devices update_engine is a
# permanently running system service, so process presence alone would pin the
# module to the long OTA timeout on every boot.
ota_detect_vendor_signal() {
    local marker value path base
    OTA_VENDOR_SIGNAL=false
    OTA_VENDOR_REASON=none

    if _ota_vendor_state_property; then
        OTA_VENDOR_SIGNAL=true
        return 0
    fi

    for marker in \
        /data/oplus/ota/update_status \
        /data/oplus/ota/update_state \
        /data/oplus/ota/status \
        /data/oplus/ota/update_progress \
        /data/oplus/ota_package/update_status \
        /data/miui/ota/update.status \
        /data/bbk/ota/update_status \
        /data/ota/last_install; do
        _ota_probe_file "$marker" || continue
        value=$(_ota_probe_read "$marker" 2>/dev/null || printf '')
        # A stale active-looking status file must not extend the boot timeout
        # forever, so an explicit recency check applies to every marker.
        if _ota_state_active "$value" && _ota_recent_path "$marker"; then
            base=${marker##*/}
            OTA_VENDOR_SIGNAL=true
            OTA_VENDOR_REASON="status_file_${base}"
            return 0
        fi
        if [ "$marker" = /data/ota/last_install ] && [ -n "$value" ] && _ota_recent_path "$marker"; then
            OTA_VENDOR_SIGNAL=true
            OTA_VENDOR_REASON=status_file_last_install
            return 0
        fi
    done

    # Vendor staging directories are useful only when they contain a recent
    # payload. A permanent empty directory is not considered an OTA signal.
    for path in /data/oplus/ota_package /data/miui/ota_package /data/ota_package; do
        _ota_probe_dir "$path" || continue
        for marker in "$path"/*.zip "$path"/payload.bin; do
            _ota_probe_file "$marker" || continue
            if _ota_recent_path "$marker"; then
                OTA_VENDOR_SIGNAL=true
                OTA_VENDOR_REASON=vendor_payload_recent
                return 0
            fi
        done
    done
    return 1
}

# Priority: explicit one-shot guard, confirmed build identity change, a live
# vendor update signal, then the pre-existing vendor/recovery heuristics.
detect_ota() {
    OTA_DETECTION_SOURCE=none
    OTA_DETECTION_REASON=none
    OTA_VENDOR_SIGNAL=false
    OTA_VENDOR_REASON=none
    if ota_baseline_is_ready; then OTA_BASELINE_READY=true; else OTA_BASELINE_READY=false; fi

    if ota_manual_flag_active; then
        OTA_DETECTION_SOURCE=manual
        OTA_DETECTION_REASON=manual_guard
        return 0
    fi
    if ota_detect_build_change; then
        OTA_DETECTION_SOURCE=build_baseline
        return 0
    fi
    OTA_DETECTION_REASON=none
    if ota_detect_vendor_signal; then
        OTA_DETECTION_SOURCE=vendor_signal
        OTA_DETECTION_REASON="$OTA_VENDOR_REASON"
        return 0
    fi
    if command -v detect_ota_legacy >/dev/null 2>&1 && detect_ota_legacy; then
        OTA_DETECTION_SOURCE=legacy
        OTA_DETECTION_REASON=legacy_signal
        return 0
    fi
    return 1
}

ota_record_detection_status() {
    local detected="${1:-false}" manual=false
    ota_manual_flag_active && manual=true
    case "$detected" in true|1|yes) detected=true ;; *) detected=false ;; esac
    {
        printf 'SCHEMA=%s\n' "$OTA_DETECTION_SCHEMA"
        printf 'DETECTED=%s\n' "$detected"
        printf 'SOURCE=%s\n' "${OTA_DETECTION_SOURCE:-none}"
        printf 'REASON=%s\n' "${OTA_DETECTION_REASON:-none}"
        printf 'BASELINE_READY=%s\n' "${OTA_BASELINE_READY:-false}"
        printf 'MANUAL_PENDING=%s\n' "$manual"
        printf 'VENDOR_SIGNAL=%s\n' "${OTA_VENDOR_SIGNAL:-false}"
        printf 'VENDOR_REASON=%s\n' "${OTA_VENDOR_REASON:-none}"
        printf 'TIMEZONE=%s\n' "$(_ota_get_timezone)"
        printf 'CHECKED_AT=%s\n' "$(_ota_now_sec)"
    } | _ota_atomic_write_stream "$OTA_DETECTION_STATUS_FILE"
}

ota_dashboard_status() {
    local source=none reason=none detected=false ready=false manual=false vendor=false vendor_reason=none timezone checked=0
    ota_baseline_is_ready && ready=true
    ota_manual_flag_active && manual=true
    timezone=$(_ota_get_timezone)
    if [ -f "$OTA_DETECTION_STATUS_FILE" ]; then
        source=$(_ota_read_key SOURCE "$OTA_DETECTION_STATUS_FILE")
        reason=$(_ota_read_key REASON "$OTA_DETECTION_STATUS_FILE")
        detected=$(_ota_read_key DETECTED "$OTA_DETECTION_STATUS_FILE")
        vendor=$(_ota_read_key VENDOR_SIGNAL "$OTA_DETECTION_STATUS_FILE")
        vendor_reason=$(_ota_read_key VENDOR_REASON "$OTA_DETECTION_STATUS_FILE")
        timezone=$(_ota_read_key TIMEZONE "$OTA_DETECTION_STATUS_FILE")
        checked=$(_ota_read_key CHECKED_AT "$OTA_DETECTION_STATUS_FILE")
    fi
    printf 'OTA_DETECTION_SOURCE=%s\n' "${source:-none}"
    printf 'OTA_DETECTION_REASON=%s\n' "${reason:-none}"
    printf 'OTA_DETECTION_ACTIVE=%s\n' "${detected:-false}"
    printf 'OTA_BASELINE_READY=%s\n' "$ready"
    printf 'OTA_MANUAL_PENDING=%s\n' "$manual"
    printf 'OTA_VENDOR_SIGNAL=%s\n' "${vendor:-false}"
    printf 'OTA_VENDOR_REASON=%s\n' "${vendor_reason:-none}"
    printf 'OTA_TIMEZONE=%s\n' "${timezone:-UTC}"
    printf 'OTA_DETECTION_CHECKED_AT=%s\n' "${checked:-0}"
}

ota_print_diagnostics() {
    local baseline_incremental baseline_patch baseline_build_id baseline_slot source reason detected ready=false manual=false vendor=false vendor_reason=none timezone
    baseline_incremental=$(_ota_read_key INCREMENTAL "$OTA_BASELINE_FILE")
    baseline_patch=$(_ota_read_key SECURITY_PATCH "$OTA_BASELINE_FILE")
    baseline_build_id=$(_ota_read_key BUILD_ID "$OTA_BASELINE_FILE")
    baseline_slot=$(_ota_read_key SLOT "$OTA_BASELINE_FILE")
    source=$(_ota_read_key SOURCE "$OTA_DETECTION_STATUS_FILE")
    reason=$(_ota_read_key REASON "$OTA_DETECTION_STATUS_FILE")
    detected=$(_ota_read_key DETECTED "$OTA_DETECTION_STATUS_FILE")
    vendor=$(_ota_read_key VENDOR_SIGNAL "$OTA_DETECTION_STATUS_FILE")
    vendor_reason=$(_ota_read_key VENDOR_REASON "$OTA_DETECTION_STATUS_FILE")
    timezone=$(_ota_read_key TIMEZONE "$OTA_DETECTION_STATUS_FILE")
    ota_baseline_is_ready && ready=true
    ota_manual_flag_active && manual=true
    printf '检测状态: %s\n' "${detected:-false}"
    printf '检测来源: %s\n' "${source:-none}"
    printf '检测原因: %s\n' "${reason:-none}"
    printf '厂商更新信号: %s (%s)\n' "${vendor:-false}" "${vendor_reason:-none}"
    printf '系统时区: %s\n' "${timezone:-$(_ota_get_timezone)}"
    printf '构建基线: %s\n' "$ready"
    printf '手动保护: %s\n' "$manual"
    printf '基线版本: build_id=%s incremental=%s patch=%s slot=%s\n' "${baseline_build_id:---}" "${baseline_incremental:---}" "${baseline_patch:---}" "${baseline_slot:---}"
    printf '当前版本: build_id=%s incremental=%s patch=%s slot=%s\n' "$(_ota_getprop ro.build.id)" "$(_ota_getprop ro.build.version.incremental)" "$(_ota_getprop ro.build.version.security_patch)" "$(_ota_normalize_slot)"
}
