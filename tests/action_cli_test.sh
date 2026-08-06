#!/usr/bin/env sh
# Host-side regression tests for RescueX action.sh's safe CLI fallback.
# Every CLI command must remain read-only: it may inspect state, but it must not
# create, delete, chmod or rewrite module state or external persistent state.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ACTION="$ROOT/action.sh"
STATE="$ROOT/webroot/state"
PERSIST="${RESCUEX_TEST_PERSIST_DIR:-$ROOT/.test-persist}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

expect_success() {
    description=$1
    shift
    output=$("$@" 2>&1) || {
        printf '%s\n' "$output" >&2
        fail "$description should succeed"
    }
    printf '%s\n' "$output"
}

expect_failure() {
    description=$1
    shift
    if output=$("$@" 2>&1); then
        printf '%s\n' "$output" >&2
        fail "$description should fail"
    fi
    printf '%s\n' "$output"
}

state_fingerprint() {
    root=$1
    [ -e "$root" ] || return 0
    # Python is available in host CI and preserves the exact bytes, modes and
    # complete tree; this avoids GNU-only find -printf assumptions.
    python - "$root" <<'PY'
from __future__ import annotations
import hashlib
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
for path in sorted(root.rglob('*')):
    info = path.lstat()
    mode = stat.S_IMODE(info.st_mode)
    rel = path.relative_to(root).as_posix()
    if path.is_symlink():
        digest = f'link:{os.readlink(path)}'
    elif path.is_file():
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
    else:
        digest = '-'
    print(f'{stat.S_IFMT(info.st_mode)}\t{mode:o}\t{info.st_size}\t{rel}\t{digest}')
PY
}

# Production keeps its existing Android default. The test redirects only its
# persistent state into an isolated local tree and fingerprints both roots.
mkdir -p "$PERSIST"
before_state=$(state_fingerprint "$STATE")
before_persist=$(state_fingerprint "$PERSIST")

run_cli() {
    RESCUEX_PERSIST_DIR="$PERSIST" sh "$ACTION" --cli "$@"
}

help_output=$(expect_success 'CLI help' run_cli help)
printf '%s\n' "$help_output" | grep -Fq 'module-changes' || fail 'help must list module-changes'
printf '%s\n' "$help_output" | grep -Fq 'safe-mode status' || fail 'help must list safe-mode status'

status_output=$(expect_success 'status command' run_cli status)
printf '%s\n' "$status_output" | grep -Fq '模块状态' || fail 'status must show module status'

health_output=$(expect_success 'health command' run_cli health)
printf '%s\n' "$health_output" | grep -Fq 'WATCHDOG_PROCESS=' || fail 'health must report watchdog process state'
printf '%s\n' "$health_output" | grep -Fq 'STATE_WRITABLE=' || fail 'health must report state directory writability'

expect_success 'timeline command' run_cli timeline >/dev/null
expect_success 'module-changes command' run_cli module-changes >/dev/null
expect_success 'snapshots command' run_cli snapshots >/dev/null
safe_mode_output=$(expect_success 'safe-mode status command' run_cli safe-mode status)
printf '%s\n' "$safe_mode_output" | grep -Fq 'STATE=' || fail 'safe-mode status must emit machine-readable state'
simulation_output=$(expect_success 'simulate command' run_cli simulate)
printf '%s\n' "$simulation_output" | grep -Fq 'ACTION=' || fail 'simulate must emit a proposed action'

unknown_output=$(expect_failure 'unknown CLI command' run_cli does-not-exist)
printf '%s\n' "$unknown_output" | grep -Fq '未知 CLI 命令' || fail 'unknown command must explain the error'

after_state=$(state_fingerprint "$STATE")
after_persist=$(state_fingerprint "$PERSIST")
[ "$before_state" = "$after_state" ] || fail 'CLI commands must not modify module state files or permissions'
[ "$before_persist" = "$after_persist" ] || fail 'CLI commands must not modify persistent state files or permissions'

rmdir "$PERSIST" 2>/dev/null || true
printf 'action CLI regression tests passed\n'
