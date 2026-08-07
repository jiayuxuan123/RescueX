#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TD=$(mktemp -d)
trap 'rm -rf "$TD"' EXIT
# Load libraries without creating runtime files in the source checkout, then
# point every mutable state path at this test's private sandbox.
MODDIR="$ROOT"; RESCUEX_PERSIST_DIR="$TD/persist"; RESCUEX_READ_ONLY=true
. "$ROOT/common.sh"
RESCUEX_READ_ONLY=false
STATE_DIR="$TD/state"; PERSIST_DIR="$TD/persist"; SNAPSHOT_DIR="$STATE_DIR/snapshots"
CONF_FILE="$STATE_DIR/config.conf"; LOG_FILE="$STATE_DIR/rescue.log"; HISTORY_FILE="$STATE_DIR/boot_history"
STATUS_FILE="$STATE_DIR/boot_status"; STATUS_TMP="$STATE_DIR/.boot_status.tmp"; JSON_FILE="$STATE_DIR/boot_status.json"
WATCHDOG_PID_FILE="$STATE_DIR/watchdog_pid"; GOOD_MODULES_FILE="$STATE_DIR/good_modules.list"; SUSPECT_LOG="$STATE_DIR/suspect_modules.log"
RESCUED_DISABLED_LIST="$STATE_DIR/rescued_disabled.list"; PATCH_FLAG_FILE="$STATE_DIR/patch_update_flag"; PATCH_FAIL_COUNT_FILE="$STATE_DIR/patch_fail_count"; PATCH_BACKUP_DIR="$STATE_DIR/patch_backup"
RESCUE_LEVEL_FILE="$STATE_DIR/rescue_level"; INTEGRITY_MANIFEST_FILE="$STATE_DIR/integrity.manifest"; INTEGRITY_STATUS_FILE="$STATE_DIR/integrity_status"
RESCUE_TXN_DIR="$PERSIST_DIR/rescue-transactions"; RESCUE_TXN_CURRENT_FILE="$STATE_DIR/rescue-transaction-current"
MODULE_BASE="$TD/modules"; MODULE_BASE_KSU=""; MODULE_BASE_AP=""; SELF_ID=RescueX
SAFE_CUSTOM_DIR_PREFIXES="$PERSIST_DIR $STATE_DIR $SNAPSHOT_DIR $TD/safe"
mkdir -p "$STATE_DIR" "$PERSIST_DIR" "$SNAPSHOT_DIR" "$MODULE_BASE/modA" "$MODULE_BASE/modB" "$TD/safe"
command -v v35_init_paths >/dev/null 2>&1 && v35_init_paths
: > "$MODULE_BASE/modA/disable"; : > "$MODULE_BASE/modB/disable"
pass=0
ok() { pass=$((pass+1)); printf 'ok %s\n' "$1"; }
# 0: A kernel-token transition is a real failure even when RTC is still zero.
# Android commonly reaches post-fs-data before date is synchronized; BOOT_TOKEN
# is the authoritative identity in that window and must not be short-circuited
# by PREV_BOOT_START=0.
(
    PREV_BOOT_RESULT=BOOTING
    PREV_BOOT_START=0
    PREV_BOOT_END=0
    PREV_BOOT_TOKEN=previous-kernel-token
    USER_REBOOT_GRACE_SEC=30
    get_boot_token() { printf '%s' current-kernel-token; }
    get_valid_epoch() { printf '%s' 0; }
    log() { :; }
    is_real_boot_failure || { echo 'token transition with zero RTC was ignored' >&2; exit 1; }
)
ok 'early boot token transition counts as failure'
# A missing/equal token must still use the conservative RTC path.
(
    PREV_BOOT_RESULT=BOOTING
    PREV_BOOT_START=0
    PREV_BOOT_END=0
    PREV_BOOT_TOKEN=same-kernel-token
    USER_REBOOT_GRACE_SEC=30
    get_boot_token() { printf '%s' same-kernel-token; }
    get_valid_epoch() { printf '%s' 0; }
    log() { :; }
    if is_real_boot_failure; then
        echo 'equal token with zero RTC was incorrectly counted' >&2
        exit 1
    fi
)
ok 'equal boot token remains conservative'
# 1: Missing evidence must not re-enable any module.
if reenable_all; then echo 'reenable unexpectedly succeeded' >&2; exit 1; fi
[ -f "$MODULE_BASE/modA/disable" ] && [ -f "$MODULE_BASE/modB/disable" ] || exit 1
ok 'missing evidence is fail-closed'
# 2: A legacy ID-only list is intentionally fail-closed; recovery needs a
# path-bound transaction so duplicate module IDs across Root managers
# cannot be accidentally re-enabled.
printf 'modA\n' > "$RESCUED_DISABLED_LIST"
if reenable_all; then echo 'legacy id-only recovery unexpectedly succeeded' >&2; exit 1; fi
[ -f "$MODULE_BASE/modA/disable" ] && [ -f "$MODULE_BASE/modB/disable" ] || exit 1
ok 'legacy id-only recovery remains fail-closed'
# 3: Exact transaction evidence restores only the marker RescueX created.
rm -f "$MODULE_BASE/modA/disable"
rescue_transaction_begin_targets test-restore
rescue_transaction_disable_target MAGISK "$MODULE_BASE" modA "$MODULE_BASE/modA"
rescue_transaction_finish_targets
[ -f "$MODULE_BASE/modA/disable" ] && [ -f "$MODULE_BASE/modB/disable" ] || exit 1
reenable_all
[ ! -f "$MODULE_BASE/modA/disable" ] && [ -f "$MODULE_BASE/modB/disable" ] || exit 1
ok 'transaction evidence restores only owned module'
# 3: Expired patch flag is removed, never treated as active.
printf 'SCHEMA=2\nEXPIRES_AT=1\n' > "$PATCH_FLAG_FILE"
if patch_flag_active; then echo 'expired patch flag accepted' >&2; exit 1; fi
[ ! -e "$PATCH_FLAG_FILE" ] || exit 1
ok 'expired patch flag is cleared'
# 4: New patch flag has schema and is active.
PATCH_FLAG_TTL_SEC=300; set_patch_flag
patch_flag_active
 grep -q '^SCHEMA=3$' "$PATCH_FLAG_FILE"
ok 'new patch flag is structured and active'
# 5: Lock excludes a second owner and can be released.
rescue_lock_acquire test
( RESCUE_LOCK_HELD=false; rescue_lock_acquire contender ) && { echo 'concurrent lock acquired' >&2; exit 1; } || true
rescue_lock_release
ok 'transaction lock excludes concurrent owner'
# 6: App unfreeze is a no-op safety refusal.
if app_unfreeze; then echo 'app unfreeze unexpectedly succeeded' >&2; exit 1; fi
[ "${APP_UNFREEZE_LAST_RESULT:-}" = MANUAL_CONFIRM_REQUIRED ] || exit 1
ok 'app unfreeze is manual-confirmation only'
# 7: A normal version upgrade rebuilds the current module baseline; a same-version change still fails.
IMOD="$TD/imod"; mkdir -p "$IMOD"
for f in module.prop common.sh v351-safety.sh watchdog.sh integrity.sh post-fs-data.sh service.sh action.sh features-v35.sh uninstall.sh; do cp "$ROOT/$f" "$IMOD/$f"; done
mkdir -p "$IMOD/webroot"
for f in index.html script.js style.css workspace-v2.css; do cp "$ROOT/webroot/$f" "$IMOD/webroot/$f"; done
MODDIR="$IMOD"
printf '#VERSION=34020\n' > "$INTEGRITY_MANIFEST_FILE"
integrity_check_once
grep -q '^RESULT=BASELINE_CREATED$' "$INTEGRITY_STATUS_FILE"
ok 'integrity upgrade rebuilds current baseline'
printf '# changed after baseline\n' >> "$IMOD/service.sh"
if integrity_check_once; then echo 'same-version tamper accepted' >&2; exit 1; fi
grep -q '^RESULT=COMPROMISED$' "$INTEGRITY_STATUS_FILE"
ok 'same-version integrity change is blocked'
# 8: service.sh may update module.prop description at runtime; that metadata
# must not turn a healthy same-version module into a false COMPROMISED state.
IMOD2="$TD/imod-mutable"; mkdir -p "$IMOD2/webroot"
for f in module.prop common.sh v351-safety.sh watchdog.sh integrity.sh post-fs-data.sh service.sh action.sh features-v35.sh uninstall.sh; do cp "$ROOT/$f" "$IMOD2/$f"; done
for f in index.html script.js style.css workspace-v2.css; do cp "$ROOT/webroot/$f" "$IMOD2/webroot/$f"; done
MODDIR="$IMOD2"
INTEGRITY_MANIFEST_FILE="$STATE_DIR/integrity.manifest"
INTEGRITY_STATUS_FILE="$STATE_DIR/integrity_status"
printf '#VERSION=34020\n' > "$INTEGRITY_MANIFEST_FILE"
integrity_check_once
grep -q '^RESULT=BASELINE_CREATED$' "$INTEGRITY_STATUS_FILE"
printf 'description=[守护中] runtime metadata\n' >> "$IMOD2/module.prop"
integrity_check_once
grep -q '^RESULT=OK$' "$INTEGRITY_STATUS_FILE"
ok 'runtime module metadata is excluded from integrity'
# 9: the native backend is opt-in and must truthfully report Shell fallback
# when the current test host is not a verified Android arm64 environment.
WATCHDOG_ENGINE=shell
engine_status=$(get_watchdog_engine_status)
printf '%s\n' "$engine_status" | grep -q '^CONFIGURED=shell$'
printf '%s\n' "$engine_status" | grep -q '^EFFECTIVE=shell$'
WATCHDOG_ENGINE=native
engine_status=$(get_watchdog_engine_status)
printf '%s\n' "$engine_status" | grep -q '^CONFIGURED=native$'
printf '%s\n' "$engine_status" | grep -q '^EFFECTIVE=shell$'
ok 'native backend remains fail-safe with Shell fallback'
# 10: v3.5.4 malformed migration lines must be repaired without losing Native.
CFG_TEST_DIR="$TD/config-test"; mkdir -p "$CFG_TEST_DIR" "$TD/config-persist"
STATE_DIR="$CFG_TEST_DIR"; CONF_FILE="$CFG_TEST_DIR/config.conf"; PERSIST_DIR="$TD/config-persist"
printf 'WATCHDOG_ENGINE=native\nCONFIG_SCHEMA_VERSION=0\n' > "$CONF_FILE"
read_config
[ "$WATCHDOG_ENGINE" = native ] || { echo 'native config was not preserved' >&2; exit 1; }
[ "$(grep -c '^WATCHDOG_ENGINE=' "$CONF_FILE")" -eq 1 ] || exit 1
[ "$(grep -c '^WATCHDOG_ENGINE=' "$PERSIST_DIR/config.conf")" -eq 1 ] || exit 1
grep -q '^WATCHDOG_ENGINE=native$' "$PERSIST_DIR/config.conf"
ok 'native config survives malformed migration and mirror sync'
# The exact old malformed duplicate must not override the valid Native choice.
printf 'WATCHDOG_ENGINE=native\nCONFIG_SCHEMA_VERSION=3\nWATCHDOG_ENGINE=shell=\n' > "$CONF_FILE"
read_config
[ "$WATCHDOG_ENGINE" = native ] || exit 1
[ "$(grep -c '^WATCHDOG_ENGINE=' "$CONF_FILE")" -eq 1 ] || exit 1
grep -q '^WATCHDOG_ENGINE=native$' "$CONF_FILE"
ok 'malformed duplicate does not downgrade Native'
# 12: startup self-heals an installer-stripped 0644 native binary.
PERM_MOD="$TD/permission-mod"; mkdir -p "$PERM_MOD/webroot/arm64-v8a"
PERM_BIN="$PERM_MOD/webroot/arm64-v8a/rescuex-watchdog"
printf '#!/bin/sh\nexit 0\n' > "$PERM_BIN"
chmod 0644 "$PERM_BIN"
MODDIR="$PERM_MOD"
ensure_watchdog_executable
[ -x "$PERM_BIN" ] || exit 1
[ "$(stat -c '%a' "$PERM_BIN")" = 755 ] || exit 1
ok 'startup repairs installer-stripped native execute bit'
# 13: a test/integrity process changing BOOTING to FAILURE cannot be overwritten
# by the late service success commit.
RACE_DIR="$TD/race"; mkdir -p "$RACE_DIR"; STATUS_FILE="$RACE_DIR/boot_status"; STATUS_TMP="$RACE_DIR/.boot_status.tmp"; JSON_FILE="$RACE_DIR/boot_status.json"; HISTORY_FILE="$RACE_DIR/boot_history"; PERSIST_DIR="$TD/race-persist"; mkdir -p "$PERSIST_DIR"
BOOT_TOKEN=race-token
write_status BOOTING 0 false 0 0 0 0 10 false
sed 's/^LAST_BOOT_RESULT=.*/LAST_BOOT_RESULT=FAILURE/' "$STATUS_FILE" > "$STATUS_FILE.tmp"; mv "$STATUS_FILE.tmp" "$STATUS_FILE"
if update_status_fields 20 1 SUCCESS 0 20 race-token; then echo 'race overwrite unexpectedly succeeded' >&2; exit 1; fi
grep -q '^LAST_BOOT_RESULT=FAILURE$' "$STATUS_FILE" || exit 1
ok 'late service cannot overwrite external failure'
printf 'all %s safety tests passed\n' "$pass"
