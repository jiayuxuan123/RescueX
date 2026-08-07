#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TD=$(mktemp -d)
trap 'rm -rf "$TD"' EXIT

# Load the real module functions without allowing library initialization to
# create runtime state in the source checkout.
MODDIR="$ROOT"
RESCUEX_PERSIST_DIR="$TD/persist"
RESCUEX_READ_ONLY=true
. "$ROOT/common.sh"
RESCUEX_READ_ONLY=false

# Isolate every mutable location used by the real classifier, rescue dispatcher
# and verified-result writer.
STATE_DIR="$TD/state"
PERSIST_DIR="$TD/persist"
SNAPSHOT_DIR="$STATE_DIR/snapshots"
CONF_FILE="$STATE_DIR/config.conf"
WHITELIST_FILE="$STATE_DIR/whitelist.conf"
STATUS_FILE="$STATE_DIR/boot_status"
STATUS_TMP="$STATE_DIR/.boot_status.tmp"
JSON_FILE="$STATE_DIR/boot_status.json"
LOG_FILE="$STATE_DIR/rescue.log"
HISTORY_FILE="$STATE_DIR/boot_history"
GOOD_MODULES_FILE="$STATE_DIR/good_modules.list"
SUSPECT_LOG="$STATE_DIR/suspect_modules.log"
RESCUE_LEVEL_FILE="$STATE_DIR/rescue_level"
RESCUED_DISABLED_LIST="$STATE_DIR/rescued_disabled.list"
RESCUE_TXN_DIR="$PERSIST_DIR/rescue-transactions"
RESCUE_TXN_CURRENT_FILE="$STATE_DIR/rescue-transaction-current"
PATCH_FLAG_FILE="$STATE_DIR/patch_update_flag"
PATCH_FAIL_COUNT_FILE="$STATE_DIR/patch_fail_count"
PATCH_BACKUP_DIR="$STATE_DIR/patch_backup"
MODULE_BASE="$TD/modules"
MODULE_BASE_KSU=""
MODULE_BASE_AP=""
SELF_ID=RescueX
DRY_RUN=false
SAFE_CUSTOM_DIR_PREFIXES="$PERSIST_DIR $STATE_DIR $SNAPSHOT_DIR"

mkdir -p "$STATE_DIR" "$PERSIST_DIR" "$SNAPSHOT_DIR" "$MODULE_BASE/badmod"
command -v v35_init_paths >/dev/null 2>&1 && v35_init_paths

# Keep observability out of this functional test; the rescue code itself,
# including actual disable-marker verification and state commit, remains real.
log() { :; }
log_rescue_action() { :; }
sync_to_persist() { :; }
append_boot_history() { :; }
_write_status_json() { :; }
take_snapshot() { printf ''; return 0; }

# Exact device condition that previously failed: early post-fs startup has no
# usable RTC (BOOT_START=0), but kernel boot identity changed.
PREV_BOOT_RESULT=BOOTING
PREV_BOOT_START=0
PREV_BOOT_END=0
PREV_BOOT_TOKEN=previous-kernel-token
USER_REBOOT_GRACE_SEC=30
get_boot_token() { printf '%s' current-kernel-token; }
get_valid_epoch() { printf '%s' 0; }

is_real_boot_failure || {
    echo 'FAIL: early token transition was not classified as a boot failure' >&2
    exit 1
}

# No known-good inventory means level 0 cannot identify one suspect. The
# dispatcher must immediately fall through to level 1 and disable badmod.
three_level_rescue || {
    echo 'FAIL: level-0-to-level-1 rescue did not complete' >&2
    exit 1
}
[ -f "$MODULE_BASE/badmod/disable" ] || {
    echo 'FAIL: level 1 did not create a verified disable marker' >&2
    exit 1
}
[ "$(tr -d '[:space:]' < "$RESCUE_LEVEL_FILE")" = 2 ] || {
    echo 'FAIL: rescue level did not advance to 2 after verified level 1' >&2
    exit 1
}

# The resulting action must be represented as a visible, durable RESCUED state.
cat > "$STATUS_FILE" <<EOF
BOOT_START=0
BOOT_TOKEN=current-kernel-token
BOOT_END=0
SERVICE_STARTED=0
FAIL_COUNT=1
LAST_BOOT_RESULT=BOOTING
OTA_DETECTED=false
RESCUE_COUNT=0
LAST_RESCUE_TIME=0
BOOT_DURATION=0
UPTIME_START=6
UPTIME_END=0
PATCH_DETECTED=false
EOF
commit_verified_rescue early-boot-test 1 || {
    echo 'FAIL: verified rescue result was not committed' >&2
    exit 1
}
grep -q '^LAST_BOOT_RESULT=RESCUED$' "$STATUS_FILE"
grep -q '^RESCUE_COUNT=1$' "$STATUS_FILE"

printf 'PASS: early token failure reaches level 1 and commits RESCUED\n'
