#!/bin/sh

set -u

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)
PASS_COUNT=0
FAIL_COUNT=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}

assert_true() {
    "$@" || fail "expected success: $*"
}

assert_false() {
    if "$@"; then
        fail "expected failure: $*"
    fi
}

assert_eq() {
    expected=$1
    actual=$2
    label=$3
    [ "$expected" = "$actual" ] || fail "$label (expected=$expected actual=$actual)"
}

assert_contains() {
    value=$1
    expected=$2
    label=$3
    case "$value" in
        *"$expected"*) return 0 ;;
        *) fail "$label (missing=$expected value=$value)" ;;
    esac
}

write_props() {
    fingerprint=$1
    incremental=$2
    security_patch=$3
    slot=$4
    system_fingerprint=${5:-$fingerprint}
    cat > "$PROPS_FILE" << EOF
ro.build.fingerprint=$fingerprint
ro.system.build.fingerprint=$system_fingerprint
ro.build.version.incremental=$incremental
ro.build.version.security_patch=$security_patch
ro.build.version.sdk=35
ro.build.version.release=15
ro.build.id=AP4A.260801.001
ro.boot.slot_suffix=$slot
EOF
}

setup_case() {
    TEST_ROOT=$(mktemp -d)
    STATE_DIR="$TEST_ROOT/state"
    PERSIST_DIR="$TEST_ROOT/persist"
    PROPS_FILE="$TEST_ROOT/props"
    mkdir -p "$STATE_DIR" "$PERSIST_DIR"
    export STATE_DIR PERSIST_DIR PROPS_FILE

    getprop() {
        awk -F= -v wanted="$1" '
            $1 == wanted {
                sub(/^[^=]*=/, "")
                print
                exit
            }
        ' "$PROPS_FILE"
    }
    log() { :; }
    detect_ota_legacy() { return 1; }

    # shellcheck source=../ota-detection.sh
    . "$PROJECT_DIR/ota-detection.sh"
}

teardown_case() {
    rm -rf "$TEST_ROOT"
}

case_missing_baseline() {
    setup_case || return 1
    write_props 'vendor/device/product:15/AP4A/100:user/release-keys' '100' '2026-08-01' '_a'
    assert_false detect_ota || return 1
    assert_eq 'false' "$OTA_BASELINE_READY" 'missing baseline readiness' || return 1
    teardown_case
}

case_identical_build() {
    setup_case || return 1
    write_props 'vendor/device/product:15/AP4A/100:user/release-keys' '100' '2026-08-01' '_a'
    assert_true ota_commit_build_baseline || return 1
    assert_true ota_baseline_is_ready || return 1
    assert_false detect_ota || return 1
    assert_eq 'none' "$OTA_DETECTION_SOURCE" 'identical build source' || return 1
    teardown_case
}

case_fingerprint_change() {
    setup_case || return 1
    write_props 'vendor/device/product:15/AP4A/100:user/release-keys' '100' '2026-08-01' '_a'
    assert_true ota_commit_build_baseline || return 1
    write_props 'vendor/device/product:16/BP1A/200:user/release-keys' '200' '2026-09-01' '_b'
    assert_true detect_ota || return 1
    assert_eq 'build_baseline' "$OTA_DETECTION_SOURCE" 'fingerprint change source' || return 1
    assert_contains "$OTA_DETECTION_REASON" 'build_fingerprint_changed' 'fingerprint change reason' || return 1
    teardown_case
}

case_incremental_and_patch_change() {
    setup_case || return 1
    fingerprint='vendor/device/product:15/AP4A/stable:user/release-keys'
    write_props "$fingerprint" '100' '2026-08-01' '_a'
    assert_true ota_commit_build_baseline || return 1
    write_props "$fingerprint" '101' '2026-09-01' '_a'
    assert_true detect_ota || return 1
    assert_contains "$OTA_DETECTION_REASON" 'incremental_changed' 'incremental change reason' || return 1
    assert_contains "$OTA_DETECTION_REASON" 'security_patch_changed' 'security patch reason' || return 1
    teardown_case
}

case_slot_change() {
    setup_case || return 1
    fingerprint='vendor/device/product:15/AP4A/stable:user/release-keys'
    write_props "$fingerprint" '100' '2026-08-01' '_a'
    assert_true ota_commit_build_baseline || return 1
    write_props "$fingerprint" '100' '2026-08-01' '_b'
    assert_true detect_ota || return 1
    assert_contains "$OTA_DETECTION_REASON" 'slot_changed' 'slot change reason' || return 1
    teardown_case
}

case_manual_guard() {
    setup_case || return 1
    write_props 'vendor/device/product:15/AP4A/100:user/release-keys' '100' '2026-08-01' '_a'
    assert_true ota_commit_build_baseline || return 1
    assert_true ota_set_manual_flag 'offline-test' || return 1
    assert_true detect_ota || return 1
    assert_eq 'manual' "$OTA_DETECTION_SOURCE" 'manual guard source' || return 1
    assert_true ota_clear_manual_flag || return 1
    assert_false ota_manual_flag_active || return 1
    teardown_case
}

case_dashboard_status() {
    setup_case || return 1
    write_props 'vendor/device/product:15/AP4A/100:user/release-keys' '100' '2026-08-01' '_a'
    assert_true ota_commit_build_baseline || return 1
    assert_true ota_set_manual_flag 'offline-test' || return 1
    assert_true detect_ota || return 1
    assert_true ota_record_detection_status true || return 1
    snapshot=$(ota_dashboard_status)
    assert_contains "$snapshot" 'OTA_DETECTION_SOURCE=manual' 'dashboard source' || return 1
    assert_contains "$snapshot" 'OTA_DETECTION_ACTIVE=true' 'dashboard active state' || return 1
    assert_contains "$snapshot" 'OTA_BASELINE_READY=true' 'dashboard baseline state' || return 1
    assert_contains "$snapshot" 'OTA_MANUAL_PENDING=true' 'dashboard manual state' || return 1
    teardown_case
}

case_legacy_fallback() {
    setup_case || return 1
    write_props 'vendor/device/product:15/AP4A/100:user/release-keys' '100' '2026-08-01' '_a'
    assert_true ota_commit_build_baseline || return 1
    detect_ota_legacy() { return 0; }
    assert_true detect_ota || return 1
    assert_eq 'legacy' "$OTA_DETECTION_SOURCE" 'legacy fallback source' || return 1
    teardown_case
}

case_corrupt_baseline() {
    setup_case || return 1
    write_props 'vendor/device/product:15/AP4A/100:user/release-keys' '100' '2026-08-01' '_a'
    printf 'SCHEMA=1\nBROKEN=1\n' > "$OTA_BASELINE_FILE"
    assert_false detect_ota || return 1
    assert_eq 'false' "$OTA_BASELINE_READY" 'corrupt baseline readiness' || return 1
    teardown_case
}

case_success_commit_order() {
    success_line=$(grep -n 'update_status_fields .*SUCCESS' "$PROJECT_DIR/service.sh" | head -n 1 | cut -d: -f1)
    baseline_line=$(grep -n 'ota_commit_build_baseline' "$PROJECT_DIR/service.sh" | head -n 1 | cut -d: -f1)
    case "$success_line:$baseline_line" in
        *[!0-9:]*|:*) fail 'service lifecycle markers missing' ;;
        *) [ "$baseline_line" -gt "$success_line" ] || fail 'baseline commit must follow SUCCESS status commit' ;;
    esac
}

case_ui_and_cli_regressions() {
    grep -q 'PATCH_FLAG_ACTIVE=true' "$PROJECT_DIR/common.sh" || fail 'dashboard does not normalize patch flag state' || return 1
    grep -q "extra.PATCH_FLAG_ACTIVE === 'true'" "$PROJECT_DIR/webroot/script.js" || fail 'WebUI still reads obsolete patch flag text' || return 1
    grep -q "DRY_RUN: 'true'" "$PROJECT_DIR/webroot/script.js" || fail 'WebUI fallback is not DRY_RUN safe' || return 1
    grep -q 'toggleOtaManualGuard' "$PROJECT_DIR/webroot/script.js" || fail 'WebUI OTA manual guard missing' || return 1
    grep -q 'run_cli_command "${2:-help}" "${3:-}" "${4:-}"' "$PROJECT_DIR/action.sh" || fail 'CLI does not forward --apply argument' || return 1
    grep -q 'common.sh ota-detection.sh' "$PROJECT_DIR/v351-safety.sh" || fail 'OTA detector missing from integrity coverage' || return 1
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

run_case 'missing baseline is not an OTA' case_missing_baseline
run_case 'identical build is not an OTA' case_identical_build
run_case 'fingerprint change is detected' case_fingerprint_change
run_case 'incremental and patch changes are detected' case_incremental_and_patch_change
run_case 'A/B slot change is detected' case_slot_change
run_case 'manual one-shot guard is detected and cleared' case_manual_guard
run_case 'dashboard reports OTA detection state' case_dashboard_status
run_case 'legacy signals remain a fallback' case_legacy_fallback
run_case 'corrupt baseline fails closed' case_corrupt_baseline
run_case 'baseline advances only after SUCCESS integration point' case_success_commit_order
run_case 'UI and CLI regressions stay covered' case_ui_and_cli_regressions

printf '\nOTA detection tests: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
