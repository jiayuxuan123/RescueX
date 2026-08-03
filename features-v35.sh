#!/system/bin/sh
# RescueX v3.5.0 feature library
# Observability-first additions. This file never scans, chmods, moves or executes
# third-party module scripts.

v35_init_paths() {
    V35_DIR="$STATE_DIR/v35"
    V35_TIMELINE_FILE="$V35_DIR/timeline.tsv"
    V35_INVENTORY_FILE="$V35_DIR/modules-good.tsv"
    V35_INVENTORY_CURRENT="$V35_DIR/modules-current.tsv"
    V35_CHANGES_FILE="$V35_DIR/module-changes.tsv"
    V35_SNAPSHOT_META_DIR="$V35_DIR/snapshot-meta"
    V35_ONESHOT_PLAN="$V35_DIR/oneshot-safe-mode.plan"
    V35_ONESHOT_APPLIED="$V35_DIR/oneshot-safe-mode.applied"
    V35_HEALTH_DIR="$V35_DIR/health.d"
    V35_INTEGRITY_DETAILS="$V35_DIR/integrity-details.tsv"
    V35_EXPORT_DIR="/sdcard/Download"
    mkdir -p "$V35_DIR" "$V35_SNAPSHOT_META_DIR" "$V35_HEALTH_DIR" 2>/dev/null
    chmod 0700 "$V35_DIR" "$V35_SNAPSHOT_META_DIR" "$V35_HEALTH_DIR" 2>/dev/null
}

v35_init_paths

v35_now() {
    local now
    now=$(date +%s 2>/dev/null)
    case "$now" in ''|*[!0-9]*) now=0 ;; esac
    printf '%s\n' "$now"
}

v35_clean_field() {
    printf '%s' "$1" | tr '\t\r\n|' '    ' | cut -c1-240
}

v35_clean_id() {
    case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
    printf '%s\n' "$1"
}

v35_atomic_file() {
    local target="$1" tmp="${1}.tmp.$$"
    mkdir -p "${target%/*}" 2>/dev/null
    cat > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    chmod 0600 "$tmp" 2>/dev/null
    mv -f "$tmp" "$target" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

v35_trim_lines() {
    local file="$1" max="$2" count tmp
    [ -f "$file" ] || return 0
    count=$(wc -l < "$file" 2>/dev/null || echo 0)
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    [ "$count" -le "$max" ] && return 0
    tmp="${file}.trim.$$"
    tail -n "$max" "$file" > "$tmp" 2>/dev/null || return 1
    chmod 0600 "$tmp" 2>/dev/null
    mv -f "$tmp" "$file" 2>/dev/null
}

# epoch<TAB>event<TAB>severity<TAB>result<TAB>detail
v35_timeline_append() {
    local event severity result detail now
    event=$(v35_clean_field "${1:-EVENT}")
    severity=$(v35_clean_field "${2:-info}")
    result=$(v35_clean_field "${3:-ok}")
    detail=$(v35_clean_field "${4:-}")
    case "$event" in ''|*[!A-Za-z0-9._-]*) event=EVENT ;; esac
    case "$severity" in info|success|warning|danger) ;; *) severity=info ;; esac
    case "$result" in ''|*[!A-Za-z0-9._-]*) result=unknown ;; esac
    now=$(v35_now)
    mkdir -p "$V35_DIR" 2>/dev/null
    printf '%s\t%s\t%s\t%s\t%s\n' "$now" "$event" "$severity" "$result" "$detail" >> "$V35_TIMELINE_FILE" 2>/dev/null || return 1
    chmod 0600 "$V35_TIMELINE_FILE" 2>/dev/null
    v35_trim_lines "$V35_TIMELINE_FILE" 300
}

v35_list_timeline() {
    [ -f "$V35_TIMELINE_FILE" ] && tail -r "$V35_TIMELINE_FILE" 2>/dev/null && return 0
    [ -f "$V35_TIMELINE_FILE" ] && awk '{ line[NR]=$0 } END { for(i=NR;i>0;i--) print line[i] }' "$V35_TIMELINE_FILE"
}

v35_find_module_dir() {
    local id="$1" base
    v35_clean_id "$id" >/dev/null || return 1
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -n "$base" ] && [ -d "$base/$id" ] && { printf '%s\n' "$base/$id"; return 0; }
    done
    return 1
}

v35_prop_value() {
    local key="$1" file="$2"
    [ -f "$file" ] || return 0
    sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -n 1 | tr '\t\r\n|' '    ' | cut -c1-96
}

v35_file_mtime() {
    local value
    value=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)
    case "$value" in ''|*[!0-9]*) value=0 ;; esac
    printf '%s\n' "$value"
}

v35_file_hash() {
    [ -f "$1" ] || { printf '%s\n' none; return; }
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | awk '{print substr($1,1,16)}'
    else
        cksum "$1" 2>/dev/null | awk '{print $1 "." $2}'
    fi
}

# id<TAB>state<TAB>versionCode<TAB>version<TAB>mtime<TAB>fingerprint
v35_collect_module_inventory() {
    local output="${1:-$V35_INVENTORY_CURRENT}" tmp="${1:-$V35_INVENTORY_CURRENT}.tmp.$$"
    local base dir id state prop version code mtime hash seen="$V35_DIR/.inventory-seen.$$"
    : > "$tmp" || return 1
    : > "$seen" || { rm -f "$tmp"; return 1; }
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -n "$base" ] && [ -d "$base" ] || continue
        for dir in "$base"/*; do
            [ -d "$dir" ] || continue
            id=$(basename "$dir")
            [ "$id" = "$SELF_ID" ] && continue
            v35_clean_id "$id" >/dev/null || continue
            grep -qxF "$id" "$seen" 2>/dev/null && continue
            printf '%s\n' "$id" >> "$seen"
            state=enabled; [ -f "$dir/disable" ] && state=disabled
            prop="$dir/module.prop"
            version=$(v35_prop_value version "$prop")
            code=$(v35_prop_value versionCode "$prop")
            case "$code" in ''|*[!0-9]*) code=0 ;; esac
            mtime=$(v35_file_mtime "$prop")
            hash=$(v35_file_hash "$prop")
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$state" "$code" "$version" "$mtime" "$hash" >> "$tmp"
        done
    done
    sort -t "$(printf '\t')" -k1,1 "$tmp" 2>/dev/null > "${tmp}.sorted" || cp "$tmp" "${tmp}.sorted"
    rm -f "$tmp" "$seen"
    chmod 0600 "${tmp}.sorted" 2>/dev/null
    mv -f "${tmp}.sorted" "$output" 2>/dev/null
}

# type<TAB>score<TAB>id<TAB>beforeState<TAB>afterState<TAB>beforeVersion<TAB>afterVersion<TAB>mtime
v35_scan_module_changes() {
    local now
    v35_collect_module_inventory "$V35_INVENTORY_CURRENT" || return 1
    if [ ! -f "$V35_INVENTORY_FILE" ]; then
        : > "$V35_CHANGES_FILE"
        chmod 0600 "$V35_CHANGES_FILE" 2>/dev/null
        return 0
    fi
    now=$(v35_now)
    awk -F '\t' -v OFS='\t' -v now="$now" '
        NR==FNR { old[$1]=$0; os[$1]=$2; ov[$1]=$4; oh[$1]=$6; next }
        { seen[$1]=1; type=""; score=0
          if (!($1 in old)) { type="added"; score=100 }
          else if (os[$1] != $2) { type="state"; score=80 }
          else if (ov[$1] != $4) { type="version"; score=90 }
          else if (oh[$1] != $6) { type="content"; score=70 }
          if (type!="") print type,score,$1,(($1 in old)?os[$1]:"missing"),$2,(($1 in old)?ov[$1]:"-"),$4,$5
        }
        END { for (id in old) if (!(id in seen)) print "removed",60,id,os[id],"missing",ov[id],"-",now }
    ' "$V35_INVENTORY_FILE" "$V35_INVENTORY_CURRENT" | sort -t "$(printf '\t')" -k2,2nr -k3,3 > "$V35_CHANGES_FILE"
    chmod 0600 "$V35_CHANGES_FILE" 2>/dev/null
    local count
    count=$(wc -l < "$V35_CHANGES_FILE" 2>/dev/null || echo 0)
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    [ "$count" -gt 0 ] && v35_timeline_append MODULE_CHANGES warning detected "count=$count"
}

v35_promote_module_inventory() {
    [ -f "$V35_INVENTORY_CURRENT" ] || v35_collect_module_inventory "$V35_INVENTORY_CURRENT" || return 1
    cp "$V35_INVENTORY_CURRENT" "$V35_INVENTORY_FILE" 2>/dev/null || return 1
    chmod 0600 "$V35_INVENTORY_FILE" 2>/dev/null
    v35_timeline_append MODULE_BASELINE success saved "count=$(wc -l < "$V35_INVENTORY_FILE" 2>/dev/null || echo 0)"
}

v35_list_module_changes() {
    [ -f "$V35_CHANGES_FILE" ] && cat "$V35_CHANGES_FILE"
}

v35_snapshot_basename() {
    local base
    base=$(basename "$1")
    case "$base" in snap-*.txt|auto-snap-latest.txt) printf '%s\n' "$base" ;; *) return 1 ;; esac
}

v35_snapshot_meta_file() {
    local base
    base=$(v35_snapshot_basename "$1") || return 1
    printf '%s/%s.meta\n' "$V35_SNAPSHOT_META_DIR" "$base"
}

v35_snapshot_name_clean() {
    local name
    name=$(v35_clean_field "$1" | cut -c1-48)
    [ -n "$name" ] || name="模块快照"
    printf '%s\n' "$name"
}

v35_write_snapshot_meta() {
    local snap="$1" name pinned="${3:-false}" type="${4:-manual}" meta created
    [ -f "$snap" ] || return 1
    meta=$(v35_snapshot_meta_file "$snap") || return 1
    name=$(v35_snapshot_name_clean "$2")
    case "$pinned" in true|false) ;; *) pinned=false ;; esac
    case "$type" in manual|auto|oneshot) ;; *) type=manual ;; esac
    created=$(v35_now)
    { printf 'NAME=%s\n' "$name"; printf 'PINNED=%s\n' "$pinned"; printf 'CREATED=%s\n' "$created"; printf 'TYPE=%s\n' "$type"; } | v35_atomic_file "$meta"
}

v35_take_named_snapshot() {
    local name="$1" snap
    snap=$(take_snapshot manual) || return 1
    v35_write_snapshot_meta "$snap" "$name" false manual || return 1
    v35_timeline_append SNAPSHOT success created "file=$(basename "$snap"),name=$(v35_snapshot_name_clean "$name")"
    printf '%s\n' "$snap"
}

v35_set_snapshot_pinned() {
    local snap="$1" pinned="$2" meta name type created
    [ -f "$snap" ] || return 1
    case "$pinned" in true|false) ;; *) return 1 ;; esac
    meta=$(v35_snapshot_meta_file "$snap") || return 1
    name=$(sed -n 's/^NAME=//p' "$meta" 2>/dev/null | head -n1); [ -n "$name" ] || name="模块快照"
    type=$(sed -n 's/^TYPE=//p' "$meta" 2>/dev/null | head -n1); [ -n "$type" ] || type=manual
    created=$(sed -n 's/^CREATED=//p' "$meta" 2>/dev/null | head -n1); [ -n "$created" ] || created=$(v35_now)
    { printf 'NAME=%s\n' "$(v35_snapshot_name_clean "$name")"; printf 'PINNED=%s\n' "$pinned"; printf 'CREATED=%s\n' "$created"; printf 'TYPE=%s\n' "$type"; } | v35_atomic_file "$meta"
    v35_timeline_append SNAPSHOT info pinned "file=$(basename "$snap"),value=$pinned"
}

v35_snapshot_meta_value() {
    local snap="$1" key="$2" meta
    meta=$(v35_snapshot_meta_file "$snap") || return 1
    sed -n "s/^${key}=//p" "$meta" 2>/dev/null | head -n1
}

# file<TAB>name<TAB>pinned<TAB>created<TAB>type<TAB>moduleCount
v35_list_snapshots_rich() {
    local snap name pinned created type count
    for snap in "$AUTO_SNAPSHOT_FILE" $(list_snapshots 2>/dev/null); do
        [ -f "$snap" ] || continue
        name=$(v35_snapshot_meta_value "$snap" NAME); [ -n "$name" ] || name=$(basename "$snap")
        pinned=$(v35_snapshot_meta_value "$snap" PINNED); [ "$pinned" = true ] || pinned=false
        created=$(v35_snapshot_meta_value "$snap" CREATED); case "$created" in ''|*[!0-9]*) created=$(v35_file_mtime "$snap") ;; esac
        type=$(v35_snapshot_meta_value "$snap" TYPE); [ -n "$type" ] || { type=manual; [ "$snap" = "$AUTO_SNAPSHOT_FILE" ] && type=auto; }
        count=$(grep -cE '^[A-Za-z0-9._-]+=(enabled|disabled)$' "$snap" 2>/dev/null || echo 0)
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$snap" "$(v35_clean_field "$name")" "$pinned" "$created" "$type" "$count"
    done
}

v35_snapshot_diff_current() {
    local snap="$1" current="$V35_DIR/.snapshot-current.$$"
    [ -f "$snap" ] || return 1
    v35_collect_module_inventory "$V35_INVENTORY_CURRENT" || return 1
    awk -F '\t' '{ print $1 "=" $2 }' "$V35_INVENTORY_CURRENT" > "$current"
    awk -F '=' -v OFS='\t' '
        NR==FNR { before[$1]=$2; next }
        { after[$1]=$2; seen[$1]=1; if (!($1 in before)) print $1,"missing",$2,"added"; else if(before[$1]!=$2) print $1,before[$1],$2,"state" }
        END { for(id in before) if(!(id in seen)) print id,before[id],"missing","removed" }
    ' "$snap" "$current" | sort
    rm -f "$current"
}

v35_restore_snapshot_selected() {
    local snap="$1" selected="$2" id state dir changed=0 skipped=0
    [ -f "$snap" ] || return 1
    case "$selected" in ''|*[!A-Za-z0-9._,-]*) return 1 ;; esac
    while IFS='=' read -r id state; do
        v35_clean_id "$id" >/dev/null || continue
        case ",$selected," in *",$id,"*) ;; *) continue ;; esac
        case "$state" in enabled|disabled) ;; *) continue ;; esac
        dir=$(v35_find_module_dir "$id") || { skipped=$((skipped + 1)); continue; }
        if [ "$state" = enabled ]; then
            rm -f "$dir/disable" 2>/dev/null && changed=$((changed + 1))
        else
            disable_module_at_dir "$dir" "$id" >/dev/null 2>&1 && changed=$((changed + 1))
        fi
    done < "$snap"
    v35_timeline_append SNAPSHOT_RESTORE warning selected "file=$(basename "$snap"),changed=$changed,skipped=$skipped"
    printf 'CHANGED=%s\nSKIPPED=%s\n' "$changed" "$skipped"
}

# Override pruning: pinned snapshots do not consume the automatic cleanup budget.
prune_manual_snapshots_in_dir() {
    local dir="$1" limit count=0 snap meta pinned
    [ -d "$dir" ] || return 0
    limit=$(get_manual_snapshot_limit)
    for snap in $(ls -1 "$dir"/snap-*.txt 2>/dev/null | sort -r); do
        [ -f "$snap" ] || continue
        if [ "$dir" = "$SNAPSHOT_DIR" ]; then
            meta=$(v35_snapshot_meta_file "$snap" 2>/dev/null)
            pinned=$(sed -n 's/^PINNED=//p' "$meta" 2>/dev/null | head -n1)
            [ "$pinned" = true ] && continue
        fi
        count=$((count + 1))
        if [ "$count" -gt "$limit" ]; then
            rm -f "$snap" 2>/dev/null
            [ "$dir" = "$SNAPSHOT_DIR" ] && rm -f "$(v35_snapshot_meta_file "$snap" 2>/dev/null)" 2>/dev/null
        fi
    done
}

v35_arm_one_shot_safe_mode() {
    local now expires snap list="$V35_DIR/.oneshot-modules.$$" base dir id
    local dry_run=false
    [ "${1:-}" = "--dry-run" ] && dry_run=true
    [ -f "$V35_ONESHOT_APPLIED" ] && return 1
    read_whitelist
    now=$(v35_now); expires=$((now + 86400))
    if [ "$dry_run" = false ]; then
        snap=$(take_snapshot manual) || return 1
        v35_write_snapshot_meta "$snap" "下一次启动安全模式" true oneshot || return 1
    fi
    : > "$list"
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -n "$base" ] && [ -d "$base" ] || continue
        for dir in "$base"/*; do
            [ -d "$dir" ] || continue
            id=$(basename "$dir")
            [ "$id" = "$SELF_ID" ] && continue
            v35_clean_id "$id" >/dev/null || continue
            [ -f "$dir/disable" ] && { printf 'SKIP:%s(already disabled)\n' "$id"; continue; }
            is_whitelisted "$id" && { printf 'SKIP:%s(whitelisted)\n' "$id"; continue; }
            grep -qxF "$id" "$list" 2>/dev/null || { printf '%s\n' "$id" >> "$list"; printf 'DISABLE:%s\n' "$id"; }
        done
    done
    if [ "$dry_run" = true ]; then
        rm -f "$list"
        printf 'PREVIEW_RC=0\n'
        return 0
    fi
    { printf 'STATE=armed\nCREATED=%s\nEXPIRES=%s\nSNAPSHOT=%s\n' "$now" "$expires" "$(basename "$snap")"; sed 's/^/MODULE=/' "$list"; } | v35_atomic_file "$V35_ONESHOT_PLAN" || { rm -f "$list"; return 1; }
    rm -f "$list"
    v35_timeline_append SAFE_MODE warning armed "snapshot=$(basename "$snap")"
    # Write standard disable markers now so the next boot starts in safe mode.
    # Exact evidence is recorded before returning; no third-party script is changed.
    v35_apply_one_shot_safe_mode || return 1
    printf 'ARMED=true\nAPPLIED=true\nSNAPSHOT=%s\n' "$snap"
}

v35_cancel_one_shot_safe_mode() {
    # Once markers were written, cancellation must use the exact transaction
    # journal; it must never enumerate or re-enable unrelated disabled modules.
    if [ -f "$V35_ONESHOT_APPLIED" ]; then
        v35_restore_one_shot_safe_mode || return 1
        v35_timeline_append SAFE_MODE info cancelled restored_exact_markers
        return 0
    fi
    [ -f "$V35_ONESHOT_PLAN" ] || return 0
    rm -f "$V35_ONESHOT_PLAN" 2>/dev/null || return 1
    v35_timeline_append SAFE_MODE info cancelled manual
}

v35_apply_one_shot_safe_mode() {
    local state expires now key id dir changed=0 tmp="$V35_ONESHOT_APPLIED.tmp.$$"
    [ -f "$V35_ONESHOT_PLAN" ] || return 0
    [ -f "$V35_ONESHOT_APPLIED" ] && return 0
    state=$(sed -n 's/^STATE=//p' "$V35_ONESHOT_PLAN" | head -n1)
    [ "$state" = armed ] || return 1
    expires=$(sed -n 's/^EXPIRES=//p' "$V35_ONESHOT_PLAN" | head -n1); now=$(v35_now)
    case "$expires" in ''|*[!0-9]*) expires=0 ;; esac
    if [ "$expires" -gt 0 ] && [ "$now" -gt "$expires" ]; then
        rm -f "$V35_ONESHOT_PLAN"
        v35_timeline_append SAFE_MODE warning expired unused
        return 0
    fi

    # Journal the exact ownership set before changing any module marker. Recovery
    # therefore remains deterministic even if power is lost during application.
    {
        printf 'STATE=prepared\nAPPLIED=%s\n' "$now"
        sed -n '/^SNAPSHOT=/p' "$V35_ONESHOT_PLAN" | head -n1
        while IFS='=' read -r key id; do
            [ "$key" = MODULE ] || continue
            v35_clean_id "$id" >/dev/null || continue
            dir=$(v35_find_module_dir "$id") || continue
            [ -f "$dir/disable" ] && continue
            printf 'MODULE=%s\n' "$id"
        done < "$V35_ONESHOT_PLAN"
    } > "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 0600 "$tmp" 2>/dev/null
    mv -f "$tmp" "$V35_ONESHOT_APPLIED" || { rm -f "$tmp"; return 1; }

    while IFS='=' read -r key id; do
        [ "$key" = MODULE ] || continue
        dir=$(v35_find_module_dir "$id") || continue
        [ -f "$dir/disable" ] && continue
        if disable_module_at_dir "$dir" "$id" >/dev/null 2>&1; then
            changed=$((changed + 1))
        fi
    done < "$V35_ONESHOT_APPLIED"
    sed 's/^STATE=prepared$/STATE=applied/' "$V35_ONESHOT_APPLIED" | v35_atomic_file "$V35_ONESHOT_APPLIED" || return 1
    sed 's/^STATE=armed$/STATE=applied/' "$V35_ONESHOT_PLAN" | v35_atomic_file "$V35_ONESHOT_PLAN" || return 1
    v35_timeline_append SAFE_MODE warning applied "disabled=$changed"
    log_rescue_action SAFE_MODE_APPLY "disabled=$changed"
}

v35_restore_one_shot_safe_mode() {
    local id dir restored=0 already_clear=0 unresolved=0 tmp="$V35_ONESHOT_APPLIED.restore.$$"
    [ -f "$V35_ONESHOT_APPLIED" ] || return 0

    # Persist the transition before changing markers. If power is lost, the next
    # successful service pass has unambiguous evidence that recovery was pending.
    sed 's/^STATE=.*/STATE=restoring/' "$V35_ONESHOT_APPLIED" | v35_atomic_file "$V35_ONESHOT_APPLIED" || return 1
    while IFS='=' read -r key id; do
        [ "$key" = MODULE ] || continue
        v35_clean_id "$id" >/dev/null || { unresolved=$((unresolved + 1)); continue; }
        dir=$(v35_find_module_dir "$id") || { unresolved=$((unresolved + 1)); continue; }
        if [ -f "$dir/disable" ]; then
            if rm -f "$dir/disable" 2>/dev/null && [ ! -f "$dir/disable" ]; then
                restored=$((restored + 1))
            else
                unresolved=$((unresolved + 1))
            fi
        else
            # Marker was already absent; it is safe to treat as recovered, but
            # keep it separately observable from a marker we removed ourselves.
            already_clear=$((already_clear + 1))
        fi
    done < "$V35_ONESHOT_APPLIED"

    if [ "$unresolved" -gt 0 ]; then
        sed 's/^STATE=.*/STATE=partial/' "$V35_ONESHOT_APPLIED" | v35_atomic_file "$V35_ONESHOT_APPLIED" || true
        v35_timeline_append SAFE_MODE warning partial_restore "restored=$restored,already_clear=$already_clear,unresolved=$unresolved"
        log_rescue_action SAFE_MODE_RESTORE_PARTIAL "restored=$restored,already_clear=$already_clear,unresolved=$unresolved"
        printf 'RESULT=PARTIAL\nRESTORED=%s\nALREADY_CLEAR=%s\nUNRESOLVED=%s\n' "$restored" "$already_clear" "$unresolved"
        # Retain both plan and applied journal for explicit retry/manual recovery.
        return 1
    fi

    rm -f "$V35_ONESHOT_APPLIED" "$V35_ONESHOT_PLAN" 2>/dev/null || return 1
    v35_timeline_append SAFE_MODE success restored "restored=$restored,already_clear=$already_clear"
    log_rescue_action SAFE_MODE_RESTORE "restored=$restored,already_clear=$already_clear"
    printf 'RESULT=RESTORED\nRESTORED=%s\nALREADY_CLEAR=%s\n' "$restored" "$already_clear"
    return 0
}

v35_one_shot_status() {
    local state=inactive created=0 expires=0 snapshot=- count=0
    [ -f "$V35_ONESHOT_PLAN" ] && {
        state=$(sed -n 's/^STATE=//p' "$V35_ONESHOT_PLAN" | head -n1)
        created=$(sed -n 's/^CREATED=//p' "$V35_ONESHOT_PLAN" | head -n1)
        expires=$(sed -n 's/^EXPIRES=//p' "$V35_ONESHOT_PLAN" | head -n1)
        snapshot=$(sed -n 's/^SNAPSHOT=//p' "$V35_ONESHOT_PLAN" | head -n1)
        count=$(grep -c '^MODULE=' "$V35_ONESHOT_PLAN" 2>/dev/null || echo 0)
    }
    [ -f "$V35_ONESHOT_APPLIED" ] && state=applied
    printf 'STATE=%s\nCREATED=%s\nEXPIRES=%s\nSNAPSHOT=%s\nMODULE_COUNT=%s\n' "$state" "$created" "$expires" "$snapshot" "$count"
}

v35_simulate_rescue() {
    local level fail threshold progressive action reason changes protected=0 candidates=0
    local readonly_prev=${RESCUEX_READ_ONLY-}
    # Simulation is observational: config parsing must not migrate or rewrite it.
    RESCUEX_READ_ONLY=true
    read_config
    if [ -n "$readonly_prev" ]; then RESCUEX_READ_ONLY=$readonly_prev; else unset RESCUEX_READ_ONLY; fi
    read_status; read_rescue_level; read_whitelist
    level=${RESCUE_LEVEL:-0}; fail=${FAIL_COUNT:-0}; threshold=${REBOOT_THRESHOLD:-3}; progressive=${PROGRESSIVE_RESCUE:-true}
    changes=$(wc -l < "$V35_CHANGES_FILE" 2>/dev/null || echo 0); case "$changes" in ''|*[!0-9]*) changes=0 ;; esac
    if patch_flag_active || [ "${PATCH_DETECTED:-false}" = true ]; then action=hold; reason=patch-window
    elif [ "$fail" -ge "$threshold" ] 2>/dev/null; then action=disable-non-whitelist; reason=threshold
    elif [ "$progressive" = true ] && [ "$fail" -ge 1 ] 2>/dev/null && [ "$changes" -gt 0 ]; then action=disable-suspects; reason=recent-changes
    elif [ "$progressive" = true ] && [ "$fail" -ge 1 ] 2>/dev/null; then action=disable-non-whitelist; reason=no-evidence-fallback
    else action=observe; reason=below-threshold; fi
    local base dir id
    for base in "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"; do
        [ -n "$base" ] && [ -d "$base" ] || continue
        for dir in "$base"/*; do
            [ -d "$dir" ] || continue; id=$(basename "$dir"); [ "$id" = "$SELF_ID" ] && continue
            v35_clean_id "$id" >/dev/null || continue
            if is_whitelisted "$id"; then protected=$((protected + 1)); else candidates=$((candidates + 1)); fi
        done
    done
    printf 'READ_ONLY=true\nACTION=%s\nREASON=%s\nFAIL_COUNT=%s\nTHRESHOLD=%s\nRESCUE_LEVEL=%s\nRECENT_CHANGES=%s\nPROTECTED=%s\nCANDIDATES=%s\n' "$action" "$reason" "$fail" "$threshold" "$level" "$changes" "$protected" "$candidates"
    [ -f "$V35_CHANGES_FILE" ] && { printf '%s\n' '--CHANGES--'; cat "$V35_CHANGES_FILE"; }
}

v35_integrity_details_update() {
    local tmp="$V35_INTEGRITY_DETAILS.tmp.$$" expected path actual state rel checked
    checked=$(v35_now); : > "$tmp" || return 1
    if [ ! -f "$INTEGRITY_MANIFEST_FILE" ]; then
        printf '%s\tmissing-baseline\t-\t-\t-\n' "$checked" > "$tmp"
    else
        while IFS=' ' read -r expected path; do
            [ -n "$expected" ] && [ -n "$path" ] || continue
            case "$path" in "$MODDIR"/*) ;; *) continue ;; esac
            rel=${path#"$MODDIR"/}
            if [ ! -f "$path" ]; then actual=-; state=missing
            else actual=$(integrity_hash_file "$path"); [ "$actual" = "$expected" ] && state=ok || state=changed
            fi
            printf '%s\t%s\t%s\t%s\t%s\n' "$checked" "$state" "$(v35_clean_field "$rel")" "$expected" "$actual" >> "$tmp"
        done < "$INTEGRITY_MANIFEST_FILE"
    fi
    chmod 0600 "$tmp" 2>/dev/null
    mv -f "$tmp" "$V35_INTEGRITY_DETAILS"
}

v35_health_touch() {
    local component="$1" state="${2:-ok}" detail file now
    case "$component" in postfs|service|watchdog|integrity) ;; *) return 1 ;; esac
    case "$state" in healthy|ok|running|stopped|warning|error) ;; *) state=warning ;; esac
    detail=$(v35_clean_field "${3:-}"); now=$(v35_now); file="$V35_HEALTH_DIR/$component"
    { printf 'COMPONENT=%s\nSTATE=%s\nUPDATED=%s\nPID=%s\nDETAIL=%s\n' "$component" "$state" "$now" "$$" "$detail"; } | v35_atomic_file "$file"
}

v35_pid_state() {
    local pidfile="$1" pid
    [ -f "$pidfile" ] || { printf '%s\n' stopped; return; }
    pid=$(cat "$pidfile" 2>/dev/null); case "$pid" in ''|*[!0-9]*) printf '%s\n' invalid; return ;; esac
    [ -d "/proc/$pid" ] && printf '%s\n' running || printf '%s\n' stale
}

v35_service_health() {
    local now file component state updated pid detail age
    now=$(v35_now)
    printf 'CHECKED=%s\nWATCHDOG_PROCESS=%s\nINTEGRITY_PROCESS=%s\nSTATE_WRITABLE=%s\nSNAPSHOT_WRITABLE=%s\n' "$now" "$(v35_pid_state "$WATCHDOG_PID_FILE")" "$(v35_pid_state "$INTEGRITY_PID_FILE")" "$([ -w "$STATE_DIR" ] && echo true || echo false)" "$([ -w "$SNAPSHOT_DIR" ] && echo true || echo false)"
    for file in "$V35_HEALTH_DIR"/*; do
        [ -f "$file" ] || continue
        component=$(sed -n 's/^COMPONENT=//p' "$file" | head -n1)
        state=$(sed -n 's/^STATE=//p' "$file" | head -n1)
        updated=$(sed -n 's/^UPDATED=//p' "$file" | head -n1); case "$updated" in ''|*[!0-9]*) updated=0 ;; esac
        pid=$(sed -n 's/^PID=//p' "$file" | head -n1)
        detail=$(sed -n 's/^DETAIL=//p' "$file" | head -n1)
        age=$((now - updated)); [ "$age" -lt 0 ] && age=0
        printf 'COMPONENT=%s|STATE=%s|UPDATED=%s|AGE=%s|PID=%s|DETAIL=%s\n' "$component" "$state" "$updated" "$age" "$pid" "$detail"
    done
}

v35_redact_stream() {
    sed -E \
        -e 's/([Tt][Oo][Kk][Ee][Nn]|[Cc][Oo][Oo][Kk][Ii][Ee]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd])=[^[:space:]]+/\1=[REDACTED]/g' \
        -e 's#(/data/user/[0-9]+/)[^/[:space:]]+#\1[APP]#g' \
        -e 's#(/data/data/)[^/[:space:]]+#\1[APP]#g'
}

v35_create_diagnostic_archive() {
    local work="$1" out="$2" zip_bin candidate busybox_bin out_base out_targz
    out_base="${out%.zip}"
    out_targz="${out_base}.tar.gz"

    # 1. System zip
    if zip_bin=$(command -v zip 2>/dev/null); then
        (cd "$work" && "$zip_bin" -qr "$out" .) && return 0
    fi

    # 2. BusyBox zip (root managers ship it outside PATH)
    for candidate in busybox /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ksu/busybox /data/adb/ap/bin/busybox; do
        case "$candidate" in
            */*) [ -x "$candidate" ] || continue; busybox_bin="$candidate" ;;
            *) busybox_bin=$(command -v "$candidate" 2>/dev/null) || continue ;;
        esac
        "$busybox_bin" zip -h >/dev/null 2>&1 || continue
        (cd "$work" && "$busybox_bin" zip -qr "$out" .) && return 0
    done

    # 3. tar + gzip — universally available on Android (toybox).
    #    Output as .tar.gz instead of .zip; any OS and GitHub can handle it.
    if command -v tar >/dev/null 2>&1 && command -v gzip >/dev/null 2>&1; then
        (cd "$work" && tar czf "$out_targz" .) && { _V35_ARCHIVE_OUT="$out_targz"; return 0; }
    fi

    # 4. Pure shell: concatenate all files into a single text bundle.
    #    No external tool required. Not a real archive, but always works.
    local f name txt_out="${out_base}.txt"
    {
        printf '=== RescueX Diagnostic Bundle (plain text fallback) ===\n\n'
        for f in "$work"/*; do
            [ -f "$f" ] || continue
            name=$(basename "$f")
            printf '\n========== %s ==========\n' "$name"
            cat "$f" 2>/dev/null || printf '(read error)\n'
        done
    } > "$txt_out" 2>/dev/null
    [ -s "$txt_out" ] && { _V35_ARCHIVE_OUT="$txt_out"; return 0; }

    return 2
}

v35_generate_diagnostic_bundle() {
    local now work out archive_rc
    now=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)
    work="$STATE_DIR/.diagnostic-$now-$$"; out="$V35_EXPORT_DIR/RescueX-diagnostic-$now.zip"
    mkdir -p "$work" "$V35_EXPORT_DIR" 2>/dev/null || return 1
    { printf 'RescueX %s (%s)\n' "$RX_VERSION" "$RX_VERSION_CODE"; printf 'generated=%s\n' "$(v35_now)"; detect_boot_mode >/dev/null 2>&1; printf 'manager=%s\n' "${MANAGER:-unknown}"; } > "$work/summary.txt"
    v35_service_health | v35_redact_stream > "$work/service-health.txt"
    v35_simulate_rescue | v35_redact_stream > "$work/rescue-simulation.txt"
    v35_one_shot_status > "$work/one-shot-safe-mode.txt"
    v35_list_snapshots_rich | v35_redact_stream > "$work/snapshots.tsv"
    [ -f "$V35_TIMELINE_FILE" ] && tail -n 200 "$V35_TIMELINE_FILE" | v35_redact_stream > "$work/timeline.tsv"
    [ -f "$V35_CHANGES_FILE" ] && cp "$V35_CHANGES_FILE" "$work/module-changes.tsv"
    [ -f "$V35_INTEGRITY_DETAILS" ] && cp "$V35_INTEGRITY_DETAILS" "$work/integrity-details.tsv"
    [ -f "$STATUS_FILE" ] && v35_redact_stream < "$STATUS_FILE" > "$work/boot-status.txt"
    [ -f "$LOG_FILE" ] && tail -n 300 "$LOG_FILE" | v35_redact_stream > "$work/rescue-log.txt"
    v35_collect_module_inventory "$work/modules.tsv" >/dev/null 2>&1
    chmod -R go-rwx "$work" 2>/dev/null
    if v35_create_diagnostic_archive "$work" "$out"; then
        out="${_V35_ARCHIVE_OUT:-$out}"
    else
        archive_rc=$?
        rm -rf "$work"
        return "$archive_rc"
    fi
    rm -rf "$work"; chmod 0600 "$out" 2>/dev/null
    v35_timeline_append DIAGNOSTIC success exported "file=$(basename "$out")"
    printf 'PATH=%s\n' "$out"
}

v35_delete_snapshot_meta() {
    local meta
    meta=$(v35_snapshot_meta_file "$1" 2>/dev/null) || return 0
    rm -f "$meta" 2>/dev/null
}
