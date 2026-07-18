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
PERSIST_DIR="$TMP_ROOT/persist"
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

cat > "$SNAPSHOT_DIR/snap-20260101-legacy-auto.txt" <<'EOF'
# RescueX 模块快照 - test
# 类型: auto
# 格式: mod_id=enabled|disabled
alpha=enabled
EOF

cat > "$SNAPSHOT_DIR/snap-20260101-manual.txt" <<'EOF'
# RescueX 模块快照 - test
# 类型: manual
# 格式: mod_id=enabled|disabled
beta=disabled
EOF

rm -f "$AUTO_SNAPSHOT_FILE"
normalize_snapshot_storage
assert_file_exists "$AUTO_SNAPSHOT_FILE" "历史自动快照应并入 auto-snap-latest"
assert_file_missing "$SNAPSHOT_DIR/snap-20260101-legacy-auto.txt" "历史自动快照文件应被清理"
assert_file_exists "$SNAPSHOT_DIR/snap-20260101-manual.txt" "手动快照应继续保留"
pass "legacy auto snapshot cleanup"

mkdir -p "$PERSIST_DIR/snapshots"
cat > "$SNAPSHOT_DIR/snap-20260101-delete-me.txt" <<'EOF'
# RescueX 模块快照 - test
# 类型: manual
# 格式: mod_id=enabled|disabled
alpha=enabled
EOF
cp "$SNAPSHOT_DIR/snap-20260101-delete-me.txt" "$PERSIST_DIR/snapshots/"
delete_snapshot "$SNAPSHOT_DIR/snap-20260101-delete-me.txt"
assert_file_missing "$SNAPSHOT_DIR/snap-20260101-delete-me.txt" "运行态快照删除应成功"
assert_file_missing "$PERSIST_DIR/snapshots/snap-20260101-delete-me.txt" "删除快照时应同步清理持久化副本"

cat > "$PERSIST_DIR/snapshots/snap-20260101-stale.txt" <<'EOF'
# RescueX 模块快照 - stale
# 类型: manual
# 格式: mod_id=enabled|disabled
alpha=enabled
EOF
sync_to_persist
assert_file_missing "$PERSIST_DIR/snapshots/snap-20260101-stale.txt" "持久化目录中的过期快照应在同步时被清理"
pass "snapshot deletion syncs persist mirror"

printf '1\n' > "$PATCH_FLAG_FILE"
printf '1\n' > "$PERSIST_DIR/patch_update_flag"
clear_patch_flag
assert_file_missing "$PATCH_FLAG_FILE" "补丁标记应从运行态删除"
assert_file_missing "$PERSIST_DIR/patch_update_flag" "补丁标记删除时应同步清理持久化副本"

printf 'alpha\n' > "$PERSIST_DIR/rescued_disabled.list"
sync_to_persist
assert_file_missing "$PERSIST_DIR/rescued_disabled.list" "已删除的救砖禁用清单不应在持久化目录残留"
pass "removable persist state cleanup"

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
