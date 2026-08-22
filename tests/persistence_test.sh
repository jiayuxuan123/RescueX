#!/bin/sh

set -u

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)
PASS_COUNT=0
FAIL_COUNT=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}

assert_file_equals() {
    expected=$1
    file=$2
    label=$3
    actual=$(cat "$file" 2>/dev/null)
    [ "$expected" = "$actual" ] || fail "$label (expected=$expected actual=$actual)"
}

setup_case() {
    TEST_ROOT=$(mktemp -d)
    MODDIR="$TEST_ROOT/module"
    export MODDIR
    export RESCUEX_PERSIST_DIR="$TEST_ROOT/persist"
    mkdir -p "$MODDIR/webroot/state"
    cp "$PROJECT_DIR/common.sh" "$PROJECT_DIR/features-v35.sh" "$PROJECT_DIR/v351-safety.sh" "$PROJECT_DIR/ota-detection.sh" "$MODDIR/"
    # shellcheck source=/dev/null
    . "$MODDIR/common.sh"
}

teardown_case() {
    rm -rf "$TEST_ROOT"
    unset RESCUEX_PERSIST_DIR MODDIR
}

case_restore_v35_from_precreated_empty_tree() {
    setup_case || return 1
    [ -d "$STATE_DIR/v35/health.d" ] || fail 'feature library did not precreate v35 state' || return 1
    mkdir -p "$PERSIST_DIR/v35/health.d"
    printf 'persisted-event\n' > "$PERSIST_DIR/v35/timeline.tsv"
    printf 'healthy\n' > "$PERSIST_DIR/v35/health.d/service"
    restore_from_persist || true
    assert_file_equals 'persisted-event' "$STATE_DIR/v35/timeline.tsv" 'v35 timeline restore' || return 1
    assert_file_equals 'healthy' "$STATE_DIR/v35/health.d/service" 'v35 nested state restore' || return 1
    teardown_case
}

case_preserve_local_v35_payload() {
    setup_case || return 1
    mkdir -p "$PERSIST_DIR/v35"
    printf 'persisted-event\n' > "$PERSIST_DIR/v35/timeline.tsv"
    printf 'current-event\n' > "$STATE_DIR/v35/timeline.tsv"
    restore_from_persist || true
    assert_file_equals 'current-event' "$STATE_DIR/v35/timeline.tsv" 'existing local v35 payload' || return 1
    teardown_case
}

case_boot_duration_history_survives_persistence() {
    setup_case || return 1
    printf '91\n93\n' > "$STATE_DIR/boot_duration_history"
    sync_to_persist || return 1
    assert_file_equals '91
93' "$PERSIST_DIR/boot_duration_history" 'duration history mirror' || return 1
    rm -f "$STATE_DIR/boot_duration_history"
    restore_from_persist || true
    assert_file_equals '91
93' "$STATE_DIR/boot_duration_history" 'duration history restore' || return 1
    teardown_case
}

run_case() {
    name=$1
    shift
    if ("$@"); then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf 'ok - %s\n' "$name"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf 'not ok - %s\n' "$name"
    fi
}

run_case 'restores v35 payload despite precreated empty directories' case_restore_v35_from_precreated_empty_tree
run_case 'preserves a current v35 payload' case_preserve_local_v35_payload
run_case 'persists adaptive boot duration history' case_boot_duration_history_survives_persistence

printf '\nPersistence tests: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
