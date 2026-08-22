#!/system/bin/sh
# RescueX system OTA detection extension.
# This library only decides whether to use the longer OTA boot timeout. It does
# not increment failures, disable modules, restore state, or schedule reboots.

OTA_DETECTION_SCHEMA=1
OTA_BASELINE_FILE="${OTA_BASELINE_FILE:-${PERSIST_DIR:-/data/adb/rescuex_data}/ota_build_baseline}"
OTA_MANUAL_FLAG_FILE="${OTA_MANUAL_FLAG_FILE:-${PERSIST_DIR:-/data/adb/rescuex_data}/ota_update_pending}"
OTA_DETECTION_STATUS_FILE="${OTA_DETECTION_STATUS_FILE:-${STATE_DIR:-${MODDIR:-/data/adb/modules/RescueX}/webroot/state}/ota_detection_status}"
OTA_DETECTION_SOURCE=none
OTA_DETECTION_REASON=none
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

# Priority: explicit one-shot guard, confirmed build identity change, then the
# pre-existing vendor/recovery/update_engine heuristics.
detect_ota() {
    OTA_DETECTION_SOURCE=none
    OTA_DETECTION_REASON=none
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
        printf 'CHECKED_AT=%s\n' "$(_ota_now_sec)"
    } | _ota_atomic_write_stream "$OTA_DETECTION_STATUS_FILE"
}

ota_dashboard_status() {
    local source=none reason=none detected=false ready=false manual=false checked=0
    ota_baseline_is_ready && ready=true
    ota_manual_flag_active && manual=true
    if [ -f "$OTA_DETECTION_STATUS_FILE" ]; then
        source=$(_ota_read_key SOURCE "$OTA_DETECTION_STATUS_FILE")
        reason=$(_ota_read_key REASON "$OTA_DETECTION_STATUS_FILE")
        detected=$(_ota_read_key DETECTED "$OTA_DETECTION_STATUS_FILE")
        checked=$(_ota_read_key CHECKED_AT "$OTA_DETECTION_STATUS_FILE")
    fi
    printf 'OTA_DETECTION_SOURCE=%s\n' "${source:-none}"
    printf 'OTA_DETECTION_REASON=%s\n' "${reason:-none}"
    printf 'OTA_DETECTION_ACTIVE=%s\n' "${detected:-false}"
    printf 'OTA_BASELINE_READY=%s\n' "$ready"
    printf 'OTA_MANUAL_PENDING=%s\n' "$manual"
    printf 'OTA_DETECTION_CHECKED_AT=%s\n' "${checked:-0}"
}

ota_print_diagnostics() {
    local baseline_incremental baseline_patch baseline_build_id baseline_slot source reason detected ready=false manual=false
    baseline_incremental=$(_ota_read_key INCREMENTAL "$OTA_BASELINE_FILE")
    baseline_patch=$(_ota_read_key SECURITY_PATCH "$OTA_BASELINE_FILE")
    baseline_build_id=$(_ota_read_key BUILD_ID "$OTA_BASELINE_FILE")
    baseline_slot=$(_ota_read_key SLOT "$OTA_BASELINE_FILE")
    source=$(_ota_read_key SOURCE "$OTA_DETECTION_STATUS_FILE")
    reason=$(_ota_read_key REASON "$OTA_DETECTION_STATUS_FILE")
    detected=$(_ota_read_key DETECTED "$OTA_DETECTION_STATUS_FILE")
    ota_baseline_is_ready && ready=true
    ota_manual_flag_active && manual=true
    printf '检测状态: %s\n' "${detected:-false}"
    printf '检测来源: %s\n' "${source:-none}"
    printf '检测原因: %s\n' "${reason:-none}"
    printf '构建基线: %s\n' "$ready"
    printf '手动保护: %s\n' "$manual"
    printf '基线版本: build_id=%s incremental=%s patch=%s slot=%s\n' "${baseline_build_id:---}" "${baseline_incremental:---}" "${baseline_patch:---}" "${baseline_slot:---}"
    printf '当前版本: build_id=%s incremental=%s patch=%s slot=%s\n' "$(_ota_getprop ro.build.id)" "$(_ota_getprop ro.build.version.incremental)" "$(_ota_getprop ro.build.version.security_patch)" "$(_ota_normalize_slot)"
}
