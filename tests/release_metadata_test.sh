#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)
VERSION='v3.5.11'
CODE='350204'

assert_contains() {
    file=$1
    value=$2
    grep -qF "$value" "$file" || {
        printf 'FAIL: %s is missing %s\n' "$file" "$value" >&2
        exit 1
    }
}

assert_contains "$PROJECT_DIR/module.prop" "version=$VERSION"
assert_contains "$PROJECT_DIR/module.prop" "versionCode=$CODE"
assert_contains "$PROJECT_DIR/common.sh" "RX_VERSION=\"$VERSION\""
assert_contains "$PROJECT_DIR/common.sh" "RX_VERSION_CODE=$CODE"
assert_contains "$PROJECT_DIR/customize.sh" "RX_VERSION=\"$VERSION\""
assert_contains "$PROJECT_DIR/webroot/script.js" "const APP_VERSION = '$VERSION';"
assert_contains "$PROJECT_DIR/webroot/script.js" "const APP_VERSION_CODE = $CODE;"
assert_contains "$PROJECT_DIR/webroot/index.html" "$VERSION"
assert_contains "$PROJECT_DIR/webroot/arm64-v8a/README.txt" "$VERSION"
assert_contains "$PROJECT_DIR/native/rescuex_watchdog.c" "$VERSION"
assert_contains "$PROJECT_DIR/webroot/index.html" "手机端导航与 OTA 识别修复"
assert_contains "$PROJECT_DIR/webroot/index.html" "md3-theme.css"
assert_contains "$PROJECT_DIR/webroot/index.html" 'class="appearance-launcher"'
assert_contains "$PROJECT_DIR/webroot/index.html" 'data-action="showAppearance"'
assert_contains "$PROJECT_DIR/webroot/script.js" "showAppearance"
assert_contains "$PROJECT_DIR/webroot/workspace-v2.css" ".workspace-hidden"
assert_contains "$PROJECT_DIR/ota-detection.sh" "ota_detect_vendor_signal"
assert_contains "$PROJECT_DIR/monet-palette.sh" "cmd overlay lookup"
assert_contains "$PROJECT_DIR/webroot/script.js" "monet-palette.sh"
if [ -e "$PROJECT_DIR/coloros-compat.sh" ]; then
    printf '%s\n' 'FAIL: ColorOS extension must not ship' >&2
    exit 1
fi
if grep -rqi 'coloros-compat' "$PROJECT_DIR/service.sh" "$PROJECT_DIR/customize.sh" "$PROJECT_DIR/v351-safety.sh" ; then
    printf '%s\n' 'FAIL: ColorOS extension references remain' >&2
    exit 1
fi
if grep -qi 'coloros_feature\|coloros-feature' "$PROJECT_DIR/webroot/index.html" "$PROJECT_DIR/webroot/script.js"; then
    printf '%s\n' 'FAIL: ColorOS WebUI surface remains' >&2
    exit 1
fi
if grep -qF 'data-action="toggleUiTheme"' "$PROJECT_DIR/webroot/index.html"; then
    printf '%s\n' 'FAIL: appearance entry must open the chooser, not switch immediately' >&2
    exit 1
fi
[ -f "$PROJECT_DIR/webui-choice.sh" ] || {
    printf 'FAIL: WebUI choice helper missing\n' >&2
    exit 1
}
[ -f "$PROJECT_DIR/monet-palette.sh" ] || {
    printf 'FAIL: Monet palette reader missing\n' >&2
    exit 1
}
[ -f "$PROJECT_DIR/webroot/md3-theme.css" ] || {
    printf 'FAIL: MD3 theme stylesheet missing\n' >&2
    exit 1
}
[ -f "$PROJECT_DIR/RELEASE-NOTES-v3.5.11.md" ] || {
    printf 'FAIL: release notes missing\n' >&2
    exit 1
}

printf 'ok - release metadata is consistent (%s / %s)\n' "$VERSION" "$CODE"
