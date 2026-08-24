#!/bin/sh

set -u

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)
PASS_COUNT=0
FAIL_COUNT=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
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
        *) fail "$label (missing=$expected)" ;;
    esac
}

refute_contains() {
    value=$1
    unexpected=$2
    label=$3
    case "$value" in
        *"$unexpected"*) fail "$label (unexpected=$unexpected)" ;;
        *) return 0 ;;
    esac
}

setup_case() {
    TEST_ROOT=$(mktemp -d) || return 1
    BIN_DIR="$TEST_ROOT/bin"
    mkdir -p "$BIN_DIR" || return 1
    PATH="$BIN_DIR:$PATH"
    export PATH
}

teardown_case() {
    rm -rf "$TEST_ROOT"
}

# A stub that answers `cmd overlay lookup ... android:color/NAME` from a table,
# mimicking the platform command the real reader depends on.
install_overlay_stub() {
    cat > "$BIN_DIR/cmd" << 'STUB'
#!/bin/sh
[ "$1" = overlay ] || exit 1
[ "$2" = lookup ] || exit 1
for arg in "$@"; do resource=$arg; done
name=${resource#android:color/}
case "$name" in
    system_accent1_0) printf '#ffffffff\n' ;;
    system_accent1_100) printf '#ffd8e2ff\n' ;;
    system_accent1_200) printf '#ffadc6ff\n' ;;
    system_accent1_600) printf '#ff3f5f90\n' ;;
    system_accent1_700) printf '#ff264777\n' ;;
    system_accent1_800) printf '#ff0b305f\n' ;;
    system_accent1_900) printf '#ff001b3d\n' ;;
    system_accent2_100) printf '#ffdae2f9\n' ;;
    system_accent2_600) printf '#ff575e71\n' ;;
    system_neutral1_10) printf '#fffdfbff\n' ;;
    system_neutral1_100) printf '#ffe3e2e6\n' ;;
    system_neutral1_500) printf '#ff8f9099\n' ;;
    system_neutral1_800) printf '#ff2f3033\n' ;;
    system_neutral1_900) printf '#ff1b1b1f\n' ;;
    system_neutral2_100) printf '#ffe1e2ec\n' ;;
    system_neutral2_200) printf '#ffc5c6d0\n' ;;
    system_neutral2_700) printf '#ff44464f\n' ;;
    *) exit 1 ;;
esac
STUB
    chmod +x "$BIN_DIR/cmd"
}

install_failing_overlay_stub() {
    printf '#!/bin/sh\nexit 1\n' > "$BIN_DIR/cmd"
    chmod +x "$BIN_DIR/cmd"
}

install_settings_stub() {
    # Write the JSON payload through a file so quoting survives into the stub.
    printf '%s' "$1" > "$TEST_ROOT/settings-value"
    cat > "$BIN_DIR/settings" << STUB
#!/bin/sh
cat "$TEST_ROOT/settings-value"
printf '\n'
STUB
    chmod +x "$BIN_DIR/settings"
}

install_empty_settings_stub() {
    printf '#!/bin/sh\nprintf "null\\n"\n' > "$BIN_DIR/settings"
    chmod +x "$BIN_DIR/settings"
}

install_getprop_stub() {
    printf '%s' "${1:-}" > "$TEST_ROOT/getprop-value"
    cat > "$BIN_DIR/getprop" << STUB
#!/bin/sh
cat "$TEST_ROOT/getprop-value"
printf '\n'
STUB
    chmod +x "$BIN_DIR/getprop"
}

# The real platform palette must be preferred over any seed approximation.
case_platform_palette_is_used() {
    setup_case || return 1
    install_overlay_stub
    install_settings_stub '{"android.theme.customization.system_palette":"3f6bd8","android.theme.customization.theme_style":"TONAL_SPOT"}'
    install_getprop_stub ''
    out=$(sh "$PROJECT_DIR/monet-palette.sh" status) || { teardown_case; return 1; }
    assert_contains "$out" 'MONET_SOURCE=platform_palette' 'palette source' || { teardown_case; return 1; }
    assert_contains "$out" 'MONET_system_accent1_600=#3f5f90' 'accent1 600 value' || { teardown_case; return 1; }
    assert_contains "$out" 'MONET_system_neutral1_900=#1b1b1f' 'neutral1 900 value' || { teardown_case; return 1; }
    assert_contains "$out" 'MONET_STYLE=TONAL_SPOT' 'theme style' || { teardown_case; return 1; }
    teardown_case
}

# Alpha must be stripped so the WebUI receives plain #rrggbb.
case_alpha_is_stripped() {
    setup_case || return 1
    install_overlay_stub
    install_empty_settings_stub
    install_getprop_stub ''
    out=$(sh "$PROJECT_DIR/monet-palette.sh" palette) || { teardown_case; return 1; }
    refute_contains "$out" '#ffd8e2ff' 'alpha retained in output' || { teardown_case; return 1; }
    assert_contains "$out" 'MONET_system_accent1_100=#d8e2ff' 'normalized accent value' || { teardown_case; return 1; }
    teardown_case
}

# Without a usable overlay command the reader must degrade to a labeled seed,
# never silently claim a real palette.
case_seed_fallback_is_labeled() {
    setup_case || return 1
    install_failing_overlay_stub
    install_settings_stub '{"android.theme.customization.system_palette":"3F6BD8"}'
    install_getprop_stub ''
    out=$(sh "$PROJECT_DIR/monet-palette.sh" status) || { teardown_case; return 1; }
    assert_contains "$out" 'MONET_SOURCE=seed_approx' 'seed fallback source' || { teardown_case; return 1; }
    assert_contains "$out" 'MONET_SEED=#3f6bd8' 'seed value' || { teardown_case; return 1; }
    refute_contains "$out" 'MONET_system_accent1_600' 'palette leaked on fallback' || { teardown_case; return 1; }
    teardown_case
}

# Nothing readable must fail closed so the WebUI keeps the static MD3 palette.
case_no_source_fails_closed() {
    setup_case || return 1
    install_failing_overlay_stub
    install_empty_settings_stub
    install_getprop_stub ''
    out=$(sh "$PROJECT_DIR/monet-palette.sh" status)
    status=$?
    assert_eq '1' "$status" 'exit status without any source' || { teardown_case; return 1; }
    assert_contains "$out" 'MONET_SOURCE=none' 'no-source marker' || { teardown_case; return 1; }
    teardown_case
}

# A vendor property seed is accepted when the AOSP setting is absent.
case_vendor_property_seed() {
    setup_case || return 1
    install_failing_overlay_stub
    install_empty_settings_stub
    install_getprop_stub '#A1B2C3'
    out=$(sh "$PROJECT_DIR/monet-palette.sh" status) || { teardown_case; return 1; }
    assert_contains "$out" 'MONET_SEED=#a1b2c3' 'vendor property seed' || { teardown_case; return 1; }
    assert_contains "$out" 'MONET_SOURCE=seed_approx' 'vendor seed source' || { teardown_case; return 1; }
    teardown_case
}

# The reader is display-only: it must never write settings or overlays.
case_reader_is_read_only() {
    if grep -Eq 'settings +put|cmd +overlay +(enable|disable|fabricate|set-priority)|setprop|pm +(disable|enable)' "$PROJECT_DIR/monet-palette.sh"; then
        fail 'Monet reader must not modify system state' || return 1
    fi
}

# The WebUI must consume the palette, not re-derive everything from one seed.
case_webui_consumes_palette() {
    grep -q 'monet-palette.sh' "$PROJECT_DIR/webroot/script.js" || fail 'WebUI does not read the platform palette' || return 1
    grep -q 'monetRolesFromPalette' "$PROJECT_DIR/webroot/script.js" || fail 'WebUI palette role mapping missing' || return 1
    grep -q 'appearance_monet_source_platform' "$PROJECT_DIR/webroot/script.js" || fail 'WebUI does not report the palette source' || return 1
    grep -q 'monet-palette.sh' "$PROJECT_DIR/v351-safety.sh" || fail 'Monet reader missing from integrity coverage' || return 1
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

run_case 'real platform palette is preferred' case_platform_palette_is_used
run_case 'alpha channel is stripped from resolved colors' case_alpha_is_stripped
run_case 'seed fallback is reported as an approximation' case_seed_fallback_is_labeled
run_case 'no readable source fails closed' case_no_source_fails_closed
run_case 'vendor property seed is accepted' case_vendor_property_seed
run_case 'palette reader never writes system state' case_reader_is_read_only
run_case 'WebUI consumes the platform palette' case_webui_consumes_palette

printf '\nMonet palette tests: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
