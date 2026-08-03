#!/bin/sh
# RescueX v3.5.0 feature regression tests.
# Every writable path is redirected to a temporary sandbox.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TD=$(mktemp -d "${TMPDIR:-/tmp}/rescuex-v35-test.XXXXXX")
trap 'rm -rf "$TD"' EXIT INT TERM

MODDIR="$ROOT"
. "$ROOT/common.sh"

STATE_DIR="$TD/state"
SNAPSHOT_DIR="$STATE_DIR/snapshots"
AUTO_SNAPSHOT_FILE="$SNAPSHOT_DIR/auto-snap-latest.txt"
AUTO_SNAPSHOT_SESSION_FILE="$STATE_DIR/auto_snapshot_session"
CONF_FILE="$STATE_DIR/config.conf"
WHITELIST_FILE="$STATE_DIR/whitelist.conf"
STATUS_FILE="$STATE_DIR/boot_status"
STATUS_TMP="$STATE_DIR/.boot_status.tmp"
LOG_FILE="$STATE_DIR/rescue.log"
HISTORY_FILE="$STATE_DIR/boot_history"
RESCUE_LEVEL_FILE="$STATE_DIR/rescue_level"
PATCH_FLAG_FILE="$STATE_DIR/patch_update_flag"
PATCH_FAIL_COUNT_FILE="$STATE_DIR/patch_fail_count"
PATCH_BACKUP_DIR="$STATE_DIR/patch_backup"
RESCUED_DISABLED_LIST="$STATE_DIR/rescued_disabled.list"
INTEGRITY_MANIFEST_FILE="$STATE_DIR/integrity.manifest"
INTEGRITY_STATUS_FILE="$STATE_DIR/integrity_status"
INTEGRITY_PID_FILE="$STATE_DIR/integrity_pid"
WATCHDOG_PID_FILE="$STATE_DIR/watchdog_pid"
PERSIST_DIR="$TD/persist"
MODULE_BASE="$TD/modules"
MODULE_BASE_KSU="$TD/modules_ksu"
MODULE_BASE_AP="$TD/modules_ap"
SELF_ID="RescueX"
MAX_MANUAL_SNAPSHOTS=1

mkdir -p "$STATE_DIR" "$SNAPSHOT_DIR" "$MODULE_BASE" "$MODULE_BASE_KSU" "$MODULE_BASE_AP"
v35_init_paths
mkdir -p "$V35_DIR" "$V35_SNAPSHOT_META_DIR" "$V35_HEALTH_DIR" "$V35_EXPORT_DIR"

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_file() { [ -f "$1" ] || fail "$2"; }
assert_not_file() { [ ! -f "$1" ] || fail "$2"; }
assert_contains() { grep -q -- "$2" "$1" || fail "$3"; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (expected=$1 actual=$2)"; }

make_module() {
    id="$1" version="${2:-1.0}" code="${3:-1}"
    mkdir -p "$MODULE_BASE/$id"
    cat > "$MODULE_BASE/$id/module.prop" <<EOF
id=$id
name=$id
version=$version
versionCode=$code
EOF
}

make_module alpha 1.0 1
make_module beta 1.0 1
make_module keep 1.0 1
make_module external 1.0 1
: > "$MODULE_BASE/external/disable"
printf 'keep\n' > "$WHITELIST_FILE"
cat > "$CONF_FILE" <<'EOF'
REBOOT_THRESHOLD=3
PROGRESSIVE_RESCUE=true
LOG_ENABLED=true
EOF
cat > "$STATUS_FILE" <<'EOF'
BOOT_START=100
BOOT_END=0
SERVICE_STARTED=0
FAIL_COUNT=1
LAST_BOOT_RESULT=BOOTING
OTA_DETECTED=false
RESCUE_COUNT=0
LAST_RESCUE_TIME=0
BOOT_DURATION=0
UPTIME_START=10
UPTIME_END=0
PATCH_DETECTED=false
EOF

# Inventory establishes a baseline and then reports only actual changes.
v35_collect_module_inventory "$V35_INVENTORY_CURRENT"
v35_promote_module_inventory
: > "$MODULE_BASE/alpha/disable"
printf 'version=1.1\n' >> "$MODULE_BASE/beta/module.prop"
v35_scan_module_changes
assert_contains "$V35_CHANGES_FILE" 'state' '模块状态变化应被识别'
assert_contains "$V35_CHANGES_FILE" 'content' '模块内容变化应被识别'
pass 'module inventory and change detection'

# A pinned snapshot must survive cleanup and selected restore must not alter other modules.
cat > "$SNAPSHOT_DIR/snap-20260101-000001.txt" <<'EOF'
# 类型: manual
alpha=enabled
beta=disabled
EOF
cat > "$SNAPSHOT_DIR/snap-20260101-000002.txt" <<'EOF'
# 类型: manual
alpha=disabled
beta=enabled
EOF
v35_write_snapshot_meta "$SNAPSHOT_DIR/snap-20260101-000001.txt" 'Pinned baseline' true manual
v35_write_snapshot_meta "$SNAPSHOT_DIR/snap-20260101-000002.txt" 'Working state' false manual
prune_manual_snapshots_in_dir "$SNAPSHOT_DIR"
assert_file "$SNAPSHOT_DIR/snap-20260101-000001.txt" '固定快照不可被自动清理'
assert_file "$SNAPSHOT_DIR/snap-20260101-000002.txt" '最新非固定快照应保留'
: > "$MODULE_BASE/beta/disable"
v35_restore_snapshot_selected "$SNAPSHOT_DIR/snap-20260101-000001.txt" alpha >/dev/null
assert_not_file "$MODULE_BASE/alpha/disable" '选择性恢复应恢复选中的 alpha'
assert_file "$MODULE_BASE/beta/disable" '选择性恢复不得修改未选中的 beta'
pass 'pinned snapshots and selected restore'

# One-shot safe mode must journal only its own writes, respect whitelist and restore exactly.
rm -f "$MODULE_BASE/alpha/disable" "$MODULE_BASE/beta/disable"
v35_arm_one_shot_safe_mode >/dev/null
assert_file "$V35_ONESHOT_APPLIED" '一次性安全模式应写入事务清单'
assert_file "$MODULE_BASE/alpha/disable" '一次性安全模式应禁用 alpha'
assert_file "$MODULE_BASE/beta/disable" '一次性安全模式应禁用 beta'
assert_not_file "$MODULE_BASE/keep/disable" '白名单模块不可被一次性安全模式禁用'
assert_file "$MODULE_BASE/external/disable" '原先禁用的外部模块应保持原状态'
assert_contains "$V35_ONESHOT_APPLIED" 'MODULE=alpha' '事务清单应包含 alpha'
assert_contains "$V35_ONESHOT_APPLIED" 'MODULE=beta' '事务清单应包含 beta'
v35_cancel_one_shot_safe_mode >/dev/null
assert_not_file "$MODULE_BASE/alpha/disable" '取消应精确恢复 alpha'
assert_not_file "$MODULE_BASE/beta/disable" '取消应精确恢复 beta'
assert_file "$MODULE_BASE/external/disable" '取消不得恢复外部预先禁用模块'
assert_not_file "$V35_ONESHOT_APPLIED" '取消后事务清单应清理'
pass 'one-shot safe mode exact ownership and cancellation'

# Simulation is observational only: it must not modify files or module markers.
before=$(find "$TD/modules" "$STATE_DIR" -type f -exec sha256sum {} \; | sort)
simulation=$(v35_simulate_rescue)
after=$(find "$TD/modules" "$STATE_DIR" -type f -exec sha256sum {} \; | sort)
assert_eq "$before" "$after" '救援模拟器不得产生文件副作用'
printf '%s\n' "$simulation" | grep -q '^READ_ONLY=true$' || fail '模拟器必须声明只读'
printf '%s\n' "$simulation" | grep -q '^ACTION=disable-suspects$' || fail '变更证据下模拟器应给出嫌疑模块策略'
pass 'read-only rescue simulation'

# Diagnostic bundle must redact simple secrets and include no raw secret value.
# The Ubuntu test image may not ship zip, so provide a temporary compatible
# wrapper that creates a real archive with Python's standard library.
FAKE_BIN="$TD/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/zip" <<'EOF'
#!/bin/sh
out=
for arg in "$@"; do
    case "$arg" in -*) ;; .) ;; *) out="$arg" ;; esac
done
[ -n "$out" ] || exit 2
python3 - "$out" <<'PY'
import os
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as archive:
    for root, _, names in os.walk("."):
        for name in names:
            path = os.path.join(root, name)
            archive.write(path, os.path.relpath(path, "."))
PY
EOF
chmod 0700 "$FAKE_BIN/zip"
printf 'token=super-secret-value\n/data/data/com.example.private/cache\n' > "$LOG_FILE"
bundle=$(PATH="$FAKE_BIN:$PATH" v35_generate_diagnostic_bundle | sed -n 's/^PATH=//p')
assert_file "$bundle" '诊断包应创建'
log_text=$(unzip -p "$bundle" rescue-log.txt)
[ -n "$log_text" ] || fail '诊断包应包含救援日志'
printf '%s\n' "$log_text" | grep -q 'token=\[REDACTED\]' || fail '诊断日志中的 token 必须脱敏'
if printf '%s\n' "$log_text" | grep -q 'super-secret-value'; then
    fail '诊断日志不得包含原始 token'
fi
pass 'diagnostic export redaction'

printf 'ALL V3.5 FEATURE TESTS PASSED\n'
