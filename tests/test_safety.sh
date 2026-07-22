#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TD=$(mktemp -d)
trap 'rm -rf "$TD"' EXIT
# Source definitions, then isolate every mutable path under a temporary sandbox.
MODDIR="$ROOT"
. "$ROOT/common.sh"
STATE_DIR="$TD/state"; PERSIST_DIR="$TD/persist"; SNAPSHOT_DIR="$STATE_DIR/snapshots"
CONF_FILE="$STATE_DIR/config.conf"; LOG_FILE="$STATE_DIR/rescue.log"; STATUS_FILE="$STATE_DIR/boot_status"; STATUS_TMP="$STATE_DIR/.boot_status.tmp"
RESCUED_DISABLED_LIST="$STATE_DIR/rescued_disabled.list"; PATCH_FLAG_FILE="$STATE_DIR/patch_update_flag"; PATCH_FAIL_COUNT_FILE="$STATE_DIR/patch_fail_count"; PATCH_BACKUP_DIR="$STATE_DIR/patch_backup"
RESCUE_LEVEL_FILE="$STATE_DIR/rescue_level"; INTEGRITY_MANIFEST_FILE="$STATE_DIR/integrity.manifest"; INTEGRITY_STATUS_FILE="$STATE_DIR/integrity_status"
MODULE_BASE="$TD/modules"; MODULE_BASE_KSU=""; MODULE_BASE_AP=""; SELF_ID=RescueX
SAFE_CUSTOM_DIR_PREFIXES="$TD/safe"
mkdir -p "$STATE_DIR" "$PERSIST_DIR" "$SNAPSHOT_DIR" "$MODULE_BASE/modA" "$MODULE_BASE/modB" "$TD/safe"
: > "$MODULE_BASE/modA/disable"; : > "$MODULE_BASE/modB/disable"
pass=0
ok() { pass=$((pass+1)); printf 'ok %s\n' "$1"; }
# 1: Missing evidence must not re-enable any module.
if reenable_all; then echo 'reenable unexpectedly succeeded' >&2; exit 1; fi
[ -f "$MODULE_BASE/modA/disable" ] && [ -f "$MODULE_BASE/modB/disable" ] || exit 1
ok 'missing evidence is fail-closed'
# 2: Exact evidence only restores recorded module.
printf 'modA\n' > "$RESCUED_DISABLED_LIST"
reenable_all
[ ! -f "$MODULE_BASE/modA/disable" ] && [ -f "$MODULE_BASE/modB/disable" ] || exit 1
ok 'exact evidence restores only recorded module'
# 3: Expired patch flag is removed, never treated as active.
printf 'SCHEMA=2\nEXPIRES_AT=1\n' > "$PATCH_FLAG_FILE"
if patch_flag_active; then echo 'expired patch flag accepted' >&2; exit 1; fi
[ ! -e "$PATCH_FLAG_FILE" ] || exit 1
ok 'expired patch flag is cleared'
# 4: New patch flag has schema and is active.
PATCH_FLAG_TTL_SEC=300; set_patch_flag
patch_flag_active
 grep -q '^SCHEMA=2$' "$PATCH_FLAG_FILE"
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
# 7: Version mismatch cannot silently rebuild integrity baseline.
# use an isolated MODDIR copy for manifest test
IMOD="$TD/imod"; mkdir -p "$IMOD"; cp "$ROOT/module.prop" "$IMOD/module.prop"
MODDIR="$IMOD"; printf '#VERSION=99999\n' > "$INTEGRITY_MANIFEST_FILE"
if integrity_check_once; then echo 'mismatched baseline accepted' >&2; exit 1; fi
grep -q '^RESULT=REVIEW_REQUIRED$' "$INTEGRITY_STATUS_FILE"
ok 'integrity version mismatch requires review'
printf 'all %s safety tests passed\n' "$pass"
