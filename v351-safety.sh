#!/system/bin/sh
# RescueX v3.5.1 safety/compatibility layer.
# Loaded after common.sh and features-v35.sh.  It intentionally overrides only
# boundary functions whose pre-v3.5.1 semantics could report a false success.

RX_CONFIG_SCHEMA_VERSION=3
RX_STATE_SCHEMA_VERSION=3

rx_is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
rx_bool() { case "$1" in true|1|yes) printf true ;; *) printf false ;; esac; }

# Keep unknown user keys, replace only the schema marker, and add new defaults
# atomically.  This may run on every boot; it writes only when migration is due.
rx_config_migrate_runtime() {
    [ -n "${CONF_FILE:-}" ] || return 1
    mkdir -p "${CONF_FILE%/*}" 2>/dev/null || return 1
    local current tmp key value changed=0
    current=$(grep '^CONFIG_SCHEMA_VERSION=' "$CONF_FILE" 2>/dev/null | head -n1 | cut -d= -f2)
    [ "$current" = "$RX_CONFIG_SCHEMA_VERSION" ] && return 0
    tmp="${CONF_FILE}.migrate.$$"
    if [ -f "$CONF_FILE" ]; then
        grep -v '^CONFIG_SCHEMA_VERSION=' "$CONF_FILE" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    else
        : > "$tmp" || return 1
    fi
    printf 'CONFIG_SCHEMA_VERSION=%s\n' "$RX_CONFIG_SCHEMA_VERSION" >> "$tmp" || { rm -f "$tmp"; return 1; }
    while IFS='|' read -r key value; do
        grep -q "^${key}=" "$tmp" 2>/dev/null || { printf '%s=%s\n' "$key" "$value" >> "$tmp"; changed=1; }
    done <<'RX_DEFAULTS'
BOOT_TIMEOUT_ADAPTIVE|true
BOOT_TIMEOUT_MIN_SEC|90
BOOT_TIMEOUT_MAX_SEC|1200
BOOT_TIMEOUT_HISTORY_SIZE|5
WATCHDOG_ENGINE|shell
WATCHDOG_HEALTH_GRACE_SEC|30
PATCH_FLAG_TTL_SEC|1800
INTEGRITY_CHECK_ENABLED|true
RX_DEFAULTS
    chmod 0600 "$tmp" 2>/dev/null
    sync "$tmp" 2>/dev/null
    mv "$tmp" "$CONF_FILE" || { rm -f "$tmp"; return 1; }
    chmod 0600 "$CONF_FILE" 2>/dev/null
    log "[CONFIG] 已迁移到 schema=${RX_CONFIG_SCHEMA_VERSION}${changed:+ 并补全缺失字段}"
    return 0
}

# Repair only the watchdog key. Older v3.5.4 builds could append malformed
# duplicate lines such as WATCHDOG_ENGINE=shell= during schema migration.
# Keep the last valid user value, remove all duplicates, and mirror it.
rx_config_repair_watchdog_engine() {
    [ -f "$CONF_FILE" ] || return 0
    local configured tmp
    configured=$(awk -F= '$1 == "WATCHDOG_ENGINE" && NF == 2 && ($2 == "native" || $2 == "shell") { value=$2 } END { print value }' "$CONF_FILE" 2>/dev/null)
    case "$configured" in native|shell) ;; *) configured=shell ;; esac
    tmp="${CONF_FILE}.watchdog.$$"
    awk -F= '$1 != "WATCHDOG_ENGINE" { print }' "$CONF_FILE" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    printf 'WATCHDOG_ENGINE=%s\n' "$configured" >> "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 0600 "$tmp" 2>/dev/null
    sync "$tmp" 2>/dev/null
    mv -f "$tmp" "$CONF_FILE" 2>/dev/null || { rm -f "$tmp"; return 1; }
    chmod 0600 "$CONF_FILE" 2>/dev/null
    sync_config_to_persist 2>/dev/null || true
    return 0
}

# Schema-aware config loader. The legacy loader remains the source of all
# historical fields, then this layer adds strictly validated v3.5.1 fields.
read_config() {
    _read_config_legacy
    CONFIG_SCHEMA_VERSION=0
    BOOT_TIMEOUT_ADAPTIVE=true
    BOOT_TIMEOUT_MIN_SEC=90
    BOOT_TIMEOUT_MAX_SEC=1200
    BOOT_TIMEOUT_HISTORY_SIZE=5
    WATCHDOG_ENGINE=shell
    PATCH_FLAG_TTL_SEC=1800
    WATCHDOG_HEALTH_GRACE_SEC=30
    APP_UNFREEZE_MANUAL_ENABLED=false
    if [ "${RESCUEX_READ_ONLY:-false}" != true ]; then
        rx_config_migrate_runtime || log "[CONFIG] 警告：运行时 schema 迁移失败，继续使用内存安全默认值"
        rx_config_repair_watchdog_engine || log "[CONFIG] 警告：WATCHDOG_ENGINE 修复失败，继续使用安全默认值"
    fi
    [ -f "$CONF_FILE" ] && {
        local k v
        while IFS='=' read -r k v; do
            case "$k" in
                CONFIG_SCHEMA_VERSION) CONFIG_SCHEMA_VERSION="$v" ;;
                BOOT_TIMEOUT_ADAPTIVE) BOOT_TIMEOUT_ADAPTIVE="$v" ;;
                BOOT_TIMEOUT_MIN_SEC) BOOT_TIMEOUT_MIN_SEC="$v" ;;
                BOOT_TIMEOUT_MAX_SEC) BOOT_TIMEOUT_MAX_SEC="$v" ;;
                BOOT_TIMEOUT_HISTORY_SIZE) BOOT_TIMEOUT_HISTORY_SIZE="$v" ;;
                WATCHDOG_ENGINE)
                    case "$v" in native|shell) WATCHDOG_ENGINE="$v" ;; esac
                    ;;
                PATCH_FLAG_TTL_SEC) PATCH_FLAG_TTL_SEC="$v" ;;
                WATCHDOG_HEALTH_GRACE_SEC) WATCHDOG_HEALTH_GRACE_SEC="$v" ;;
                APP_UNFREEZE_MANUAL_ENABLED) APP_UNFREEZE_MANUAL_ENABLED="$v" ;;
            esac
        done < "$CONF_FILE"
    }
    rx_is_uint "$CONFIG_SCHEMA_VERSION" || CONFIG_SCHEMA_VERSION=0
    rx_is_uint "$BOOT_TIMEOUT_MIN_SEC" || BOOT_TIMEOUT_MIN_SEC=90
    rx_is_uint "$BOOT_TIMEOUT_MAX_SEC" || BOOT_TIMEOUT_MAX_SEC=1200
    rx_is_uint "$BOOT_TIMEOUT_HISTORY_SIZE" || BOOT_TIMEOUT_HISTORY_SIZE=5
    rx_is_uint "$PATCH_FLAG_TTL_SEC" || PATCH_FLAG_TTL_SEC=1800
    rx_is_uint "$WATCHDOG_HEALTH_GRACE_SEC" || WATCHDOG_HEALTH_GRACE_SEC=30
    [ "$BOOT_TIMEOUT_MIN_SEC" -lt 60 ] 2>/dev/null && BOOT_TIMEOUT_MIN_SEC=60
    [ "$BOOT_TIMEOUT_MIN_SEC" -gt 600 ] 2>/dev/null && BOOT_TIMEOUT_MIN_SEC=600
    [ "$BOOT_TIMEOUT_MAX_SEC" -lt "$BOOT_TIMEOUT_MIN_SEC" ] 2>/dev/null && BOOT_TIMEOUT_MAX_SEC="$BOOT_TIMEOUT_MIN_SEC"
    [ "$BOOT_TIMEOUT_MAX_SEC" -gt 1800 ] 2>/dev/null && BOOT_TIMEOUT_MAX_SEC=1800
    [ "$BOOT_TIMEOUT_HISTORY_SIZE" -lt 3 ] 2>/dev/null && BOOT_TIMEOUT_HISTORY_SIZE=3
    [ "$BOOT_TIMEOUT_HISTORY_SIZE" -gt 10 ] 2>/dev/null && BOOT_TIMEOUT_HISTORY_SIZE=10
    [ "$PATCH_FLAG_TTL_SEC" -lt 300 ] 2>/dev/null && PATCH_FLAG_TTL_SEC=300
    [ "$PATCH_FLAG_TTL_SEC" -gt 7200 ] 2>/dev/null && PATCH_FLAG_TTL_SEC=7200
    [ "$WATCHDOG_HEALTH_GRACE_SEC" -lt 10 ] 2>/dev/null && WATCHDOG_HEALTH_GRACE_SEC=10
    [ "$WATCHDOG_HEALTH_GRACE_SEC" -gt 120 ] 2>/dev/null && WATCHDOG_HEALTH_GRACE_SEC=120
    BOOT_TIMEOUT_ADAPTIVE=$(rx_bool "$BOOT_TIMEOUT_ADAPTIVE")
    case "$WATCHDOG_ENGINE" in native|shell) ;; *) WATCHDOG_ENGINE=shell ;; esac
    APP_UNFREEZE_MANUAL_ENABLED=false
}

rx_boot_history_file() { printf '%s' "$STATE_DIR/boot_duration_history"; }

# A valid successful duration is persisted in an atomic rolling window. RTC is
# not used: service provides the uptime-derived value already stored in status.
record_boot_duration() {
    local duration="$1" file tmp count=0 line
    rx_is_uint "$duration" || return 1
    [ "$duration" -ge 20 ] 2>/dev/null || return 1
    [ "$duration" -le 3600 ] 2>/dev/null || return 1
    file=$(rx_boot_history_file); tmp="${file}.tmp.$$"
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    : > "$tmp" || return 1
    if [ -f "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            rx_is_uint "$line" || continue
            [ "$line" -ge 20 ] 2>/dev/null || continue
            [ "$line" -le 3600 ] 2>/dev/null || continue
            printf '%s\n' "$line" >> "$tmp"
            count=$((count + 1))
            [ "$count" -ge "$BOOT_TIMEOUT_HISTORY_SIZE" ] && break
        done < "$file"
    fi
    # Newest first. Keep exactly the requested moving average window.
    { printf '%s\n' "$duration"; cat "$tmp"; } > "${tmp}.new" || { rm -f "$tmp" "${tmp}.new"; return 1; }
    sed -n "1,${BOOT_TIMEOUT_HISTORY_SIZE}p" "${tmp}.new" > "$tmp"
    rm -f "${tmp}.new"
    chmod 0600 "$tmp" 2>/dev/null; sync "$tmp" 2>/dev/null; mv "$tmp" "$file" || return 1
    chmod 0600 "$file" 2>/dev/null
}

get_effective_boot_timeout() {
    local base avg=0 sum=0 count=0 line candidate file
    base="$BOOT_TIMEOUT_SEC"; rx_is_uint "$base" || base=90
    [ "$BOOT_TIMEOUT_ADAPTIVE" = true ] || { printf '%s' "$base"; return 0; }
    file=$(rx_boot_history_file)
    if [ -f "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            rx_is_uint "$line" || continue
            [ "$line" -ge 20 ] 2>/dev/null || continue
            [ "$line" -le 3600 ] 2>/dev/null || continue
            sum=$((sum + line)); count=$((count + 1))
            [ "$count" -ge "$BOOT_TIMEOUT_HISTORY_SIZE" ] && break
        done < "$file"
    fi
    if [ "$count" -gt 0 ]; then
        avg=$((sum / count))
        # 2x mean gives slow devices a cushion but is capped by an explicit
        # user-controlled maximum. Never lower an existing manual timeout.
        candidate=$((avg * 2))
        [ "$candidate" -gt "$base" ] && base="$candidate"
    fi
    [ "$base" -lt "$BOOT_TIMEOUT_MIN_SEC" ] 2>/dev/null && base="$BOOT_TIMEOUT_MIN_SEC"
    [ "$base" -gt "$BOOT_TIMEOUT_MAX_SEC" ] 2>/dev/null && base="$BOOT_TIMEOUT_MAX_SEC"
    printf '%s' "$base"
}

# The native binary is deliberately optional. A prebuilt is used only after
# architecture, execute bit and launcher self-test pass; otherwise shell stays
# authoritative. Native binary invokes watchdog.sh once at its deadline.
# v3.5.6: KSU-compatible installers may unpack the binary as 0644 even when
# the ZIP entry is 0755. Repair the exact module-owned file before checking or
# launching it; a noexec mount still fails later at the real self-test.
ensure_watchdog_executable() {
    local bin="$MODDIR/webroot/arm64-v8a/rescuex-watchdog"
    [ -f "$bin" ] || return 1
    chmod 0755 "$bin" 2>/dev/null || true
    [ -x "$bin" ]
}

get_watchdog_engine() {
    local bin="$MODDIR/webroot/arm64-v8a/rescuex-watchdog"
    [ "$WATCHDOG_ENGINE" = native ] || { printf shell; return 0; }
    [ "$(getprop ro.product.cpu.abi 2>/dev/null)" = arm64-v8a ] || { printf shell; return 0; }
    ensure_watchdog_executable || { printf shell; return 0; }
    "$bin" --self-test >/dev/null 2>&1 || { printf shell; return 0; }
    printf native
}

get_watchdog_engine_status() {
    local configured="${WATCHDOG_ENGINE:-shell}" effective=shell reason=shell_selected
    local bin="$MODDIR/webroot/arm64-v8a/rescuex-watchdog" abi
    case "$configured" in native|shell) ;; *) configured=shell ;; esac
    abi=$(getprop ro.product.cpu.abi 2>/dev/null || true)
    if [ "$configured" = native ]; then
        if [ "$abi" != arm64-v8a ]; then
            reason=not_arm64
        elif [ ! -e "$bin" ]; then
            reason=missing_binary
        elif ! ensure_watchdog_executable; then
            reason=not_executable
        elif ! "$bin" --self-test >/dev/null 2>&1; then
            reason=self_test_failed
        else
            effective=native
            reason=ready
        fi
    fi
    printf 'CONFIGURED=%s\nEFFECTIVE=%s\nREASON=%s\nABI=%s\n' "$configured" "$effective" "$reason" "$abi"
}

# Full rescue is successful only when an actual disable marker was verified.
# DRY_RUN produces an explicit simulation result but cannot be committed as
# RESCUED by automated watchdog paths.
full_rescue() {
    local disabled=0 skipped=0 failed=0 base mod_id mod_dir auto_snap
    read_whitelist
    log "全量救砖：禁用所有非白名单模块（v3.5.1 验证模式）"
    auto_snap=$(take_snapshot auto); [ -n "$auto_snap" ] && log "救砖前自动快照: $(basename "$auto_snap")"
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -n "$base" ] && [ -d "$base" ] || continue
        for mod_dir in "$base"/*/; do
            [ -d "$mod_dir" ] || continue
            mod_id=$(basename "$mod_dir")
            case "$mod_id" in ''|*[!A-Za-z0-9._-]*|"$SELF_ID") skipped=$((skipped + 1)); continue ;; esac
            is_whitelisted "$mod_id" && { skipped=$((skipped + 1)); continue; }
            [ -f "${mod_dir}disable" ] && { skipped=$((skipped + 1)); continue; }
            if [ "$DRY_RUN" = true ]; then
                log "[DRY_RUN] 将禁用: $mod_id"; disabled=$((disabled + 1)); continue
            fi
            if disable_module_at_dir "$mod_dir" "$mod_id" && [ -f "${mod_dir}disable" ]; then
                printf '%s\n' "$mod_id" >> "$RESCUED_DISABLED_LIST" 2>/dev/null
                disabled=$((disabled + 1))
            else
                failed=$((failed + 1)); log "禁用失败: $mod_id"
            fi
        done
    done
    log_rescue_action FULL_RESCUE "verified_disabled=$disabled,skipped=$skipped,failed=$failed,dry_run=$DRY_RUN"
    if [ "$DRY_RUN" = true ]; then
        log "[WD] DRY_RUN 不提交 RESCUED；仅完成模拟"; return 2
    fi
    [ "$disabled" -gt 0 ] || { log "[WD] 全量救砖未验证任何 disable 标记，拒绝提交成功"; return 1; }
    [ "$failed" -eq 0 ] || { log "[WD] 部分模块禁用失败，拒绝提交成功"; return 1; }
    return 0
}

full_rescue_with_scripts() {
    log "===== 级别 1: 全量救砖（验证写入）====="
    full_rescue || return $?
    write_rescue_level 2 || return 1
    log_rescue_action FULL_RESCUE_VERIFIED "exact_disable_markers_verified"
    return 0
}

_three_level_rescue_unlocked() {
    read_rescue_level
    case "$RESCUE_LEVEL" in
        0)
            log "当前救砖级别: 0 → 尝试精准嫌疑禁用"
            suspect_rescue && return 0
            log "嫌疑禁用未产生已验证动作，升级到全量救砖"
            full_rescue_with_scripts
            ;;
        1) full_rescue_with_scripts ;;
        2) log "级别 2 的 APP 解冻已永久退役；拒绝伪成功"; app_unfreeze; return 1 ;;
        *) write_rescue_level 1; full_rescue_with_scripts ;;
    esac
}

# Expand non-cryptographic integrity coverage. This remains tamper detection,
# not anti-root attestation; release signatures are handled outside the module.
# module.prop is excluded because service.sh intentionally refreshes its description.
integrity_target_files() {
    printf '%s\n' common.sh v351-safety.sh watchdog.sh integrity.sh post-fs-data.sh service.sh action.sh features-v35.sh uninstall.sh webroot/index.html webroot/script.js webroot/style.css webroot/workspace-v2.css
}

# A boot is healthy only after a committed SUCCESS state, never merely because
# service began. This prevents the watchdog from accepting a partial boot.
boot_health_confirmed() {
    local result end
    [ -f "$STATUS_FILE" ] || return 1
    result=$(grep '^LAST_BOOT_RESULT=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    end=$(grep '^BOOT_END=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2)
    rx_is_uint "$end" || end=0
    [ "$result" = SUCCESS ] && [ "$end" -gt 0 ]
}

# Run only after the watchdog's final health check. A dry-run, lock conflict,
# failed action or stale invocation is never promoted to RESCUED.
watchdog_trigger() {
    boot_health_confirmed && { log "[WD] 已提交 SUCCESS，忽略迟到触发"; return 0; }
    rescue_lock_acquire watchdog || { log "[WD] 锁被占用，拒绝重复救砖"; return 1; }
    rescue_transaction_begin WATCHDOG_RESCUE || { rescue_lock_release; return 1; }
    _watchdog_trigger_unlocked
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        rescue_transaction_end WATCHDOG_RESCUE || rc=1
    else
        rescue_transaction_fail WATCHDOG_RESCUE_FAILED
    fi
    rescue_lock_release
    return "$rc"
}

# Avoid treating DRY_RUN's simulated module changes as a real rescue action.
_three_level_rescue_unlocked() {
    [ "$DRY_RUN" = true ] && { log "[WD] DRY_RUN：拒绝提交自动救砖或重启"; log_rescue_action RESCUE_SIMULATED watchdog; return 2; }
    read_rescue_level
    case "$RESCUE_LEVEL" in
        0)
            log "当前救砖级别: 0 → 尝试精准嫌疑禁用"
            suspect_rescue && return 0
            log "嫌疑禁用未产生已验证动作，升级到全量救砖"
            full_rescue_with_scripts
            ;;
        1) full_rescue_with_scripts ;;
        2) log "级别 2 的 APP 解冻已永久退役；拒绝伪成功"; app_unfreeze; return 1 ;;
        *) write_rescue_level 1; full_rescue_with_scripts ;;
    esac
}
