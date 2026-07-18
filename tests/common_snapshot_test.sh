#!/bin/sh

set -eu

TMP_ROOT="${TMPDIR:-/tmp}/rescuex-common-test.$$"
mkdir -p "$TMP_ROOT/mod/webroot/state/snapshots"
mkdir -p "$TMP_ROOT/modules" "$TMP_ROOT/modules_ksu" "$TMP_ROOT/modules_ap"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

MODDIR="$TMP_ROOT/mod"
. /workspace/common.sh

STATE_DIR="$TMP_ROOT/mod/webroot/state"
SNAPSHOT_DIR="$STATE_DIR/snapshots"
AUTO_SNAPSHOT_FILE="$SNAPSHOT_DIR/auto-snap-latest.txt"
AUTO_SNAPSHOT_SESSION_FILE="$STATE_DIR/auto_snapshot_session"
MODULE_BASE="$TMP_ROOT/modules"
MODULE_BASE_KSU="$TMP_ROOT/modules_ksu"
MODULE_BASE_AP="$TMP_ROOT/modules_ap"
SELF_ID="RescueX"
MAX_MANUAL_SNAPSHOTS=3

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    [ "$1" = "$2" ] || fail "$3 (expected '$1', got '$2')"
}

assert_file_exists() {
    [ -f "$1" ] || fail "$2"
}

assert_file_missing() {
    [ ! -f "$1" ] || fail "$2"
}

module_dir() {
    mkdir -p "$MODULE_BASE/$1"
}

set_disabled() {
    : > "$MODULE_BASE/$1/disable"
}

set_boot_status() {
    cat > "$STATUS_FILE" <<EOF
BOOT_START=$1
BOOT_END=0
SERVICE_STARTED=0
FAIL_COUNT=1
LAST_BOOT_RESULT=BOOTING
OTA_DETECTED=false
RESCUE_COUNT=0
LAST_RESCUE_TIME=0
BOOT_DURATION=0
UPTIME_START=$2
UPTIME_END=0
PATCH_DETECTED=false
EOF
}

module_dir alpha
module_dir beta
module_dir gamma

set_disabled beta

for ts in 000001 000002 000003 000004 000005; do
    printf '# sample %s\n' "$ts" > "$SNAPSHOT_DIR/snap-20260101-${ts}.txt"
done
prune_manual_snapshots_in_dir "$SNAPSHOT_DIR"

count=$(ls "$SNAPSHOT_DIR"/snap-*.txt 2>/dev/null | wc -l | tr -d ' ')
assert_eq 3 "$count" "手动快照应裁剪到保留上限"
assert_file_missing "$SNAPSHOT_DIR/snap-20260101-000001.txt" "最旧快照应被裁剪"
assert_file_exists "$SNAPSHOT_DIR/snap-20260101-000005.txt" "最新快照应保留"
pass "manual snapshot pruning"

set_boot_status 100 10
rm -f "$MODULE_BASE/alpha/disable"
take_snapshot auto >/dev/null
assert_file_exists "$AUTO_SNAPSHOT_FILE" "自动快照文件应创建"
grep -q '^alpha=enabled$' "$AUTO_SNAPSHOT_FILE" || fail "首次自动快照应记录初始状态"
assert_eq 'boot:100' "$(cat "$AUTO_SNAPSHOT_SESSION_FILE")" "自动快照会话应写入当前 boot_start"

set_disabled alpha
take_snapshot auto >/dev/null
grep -q '^alpha=enabled$' "$AUTO_SNAPSHOT_FILE" || fail "同一启动会话内自动快照应只生成一次"

set_boot_status 200 20
take_snapshot auto >/dev/null
grep -q '^alpha=disabled$' "$AUTO_SNAPSHOT_FILE" || fail "新启动会话应刷新自动快照"
assert_eq 'boot:200' "$(cat "$AUTO_SNAPSHOT_SESSION_FILE")" "自动快照会话应跟随新 boot_start 刷新"
pass "auto snapshot session dedupe"

cat > "$SNAPSHOT_DIR/snap-invalid.txt" <<'EOF'
# malformed snapshot
alpha=disabled
beta=bogus
../../evil=enabled
EOF

rm -f "$MODULE_BASE/alpha/disable" "$MODULE_BASE/beta/disable"
restore_snapshot "$SNAPSHOT_DIR/snap-invalid.txt"
assert_file_exists "$MODULE_BASE/alpha/disable" "合法状态应被恢复"
assert_file_missing "$MODULE_BASE/beta/disable" "非法状态值应被忽略"
pass "snapshot state validation"

mkdir -p /data/adb/lsposed/disable_config
state=$(detect_lsposed_state)
rmdir /data/adb/lsposed/disable_config
rmdir /data/adb/lsposed 2>/dev/null || true
assert_eq "disabled (legacy)" "$state" "legacy LSPosed 状态应被识别"
pass "legacy lsposed detection"

printf 'ALL TESTS PASSED\n'
