#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)
VERSION='v3.5.10-r3'
CODE='350203'

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
assert_contains "$PROJECT_DIR/webroot/index.html" "系统 OTA 检测与升级可靠性修复"
[ -f "$PROJECT_DIR/RELEASE-NOTES-v3.5.10-r3.md" ] || {
    printf 'FAIL: release notes missing\n' >&2
    exit 1
}

printf 'ok - release metadata is consistent (%s / %s)\n' "$VERSION" "$CODE"
