#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PYTHON_BIN=
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" --version >/dev/null 2>&1; then
        PYTHON_BIN=$candidate
        break
    fi
done
[ -n "$PYTHON_BIN" ] || { printf 'PYTHON_NOT_FOUND\n' >&2; exit 1; }

required='META-INF/com/google/android/updater-script META-INF/com/google/android/update-binary module.prop customize.sh common.sh ota-detection.sh features-v35.sh post-fs-data.sh service.sh watchdog.sh integrity.sh action.sh uninstall.sh webroot/index.html webroot/script.js webroot/style.css update.json'
for file in $required; do
    [ -e "$file" ] || { printf 'MISSING: %s\n' "$file" >&2; exit 1; }
done

# Git for Windows does not treat an Android ELF as directly executable even
# when its archive mode is 0755. The release ZIP test verifies that mode.
if [ ! -x webroot/arm64-v8a/rescuex-watchdog ]; then
    case "$(uname -s 2>/dev/null || echo unknown)" in
        MINGW*|MSYS*) ;;
        *) printf 'NATIVE_WATCHDOG_MISSING_OR_NOT_EXECUTABLE\n' >&2; exit 1 ;;
    esac
fi
file webroot/arm64-v8a/rescuex-watchdog | grep -Eq 'AArch64|arm64' || { printf 'NATIVE_WATCHDOG_NOT_AARCH64\n' >&2; exit 1; }
if command -v readelf >/dev/null 2>&1; then
    readelf -l webroot/arm64-v8a/rescuex-watchdog | grep -q '/system/bin/linker64' || { printf 'NATIVE_WATCHDOG_NOT_ANDROID_PIE\n' >&2; exit 1; }
else
    # Keep release validation usable on Windows hosts without binutils. The
    # archive test separately verifies the executable mode and non-empty bytes.
    grep -aq '/system/bin/linker64' webroot/arm64-v8a/rescuex-watchdog || { printf 'NATIVE_WATCHDOG_NOT_ANDROID_PIE\n' >&2; exit 1; }
fi

for file in *.sh; do
    sh -n "$file"
done
node --check webroot/script.js
"$PYTHON_BIN" -c 'import json; json.load(open("update.json", encoding="utf-8"))'

version=$(awk -F= '$1 == "version" { print $2; exit }' module.prop)
version_code=$(awk -F= '$1 == "versionCode" { print $2; exit }' module.prop)
json_version=$("$PYTHON_BIN" -c 'import json; print(json.load(open("update.json", encoding="utf-8"))["version"])')
json_version_code=$("$PYTHON_BIN" -c 'import json; print(json.load(open("update.json", encoding="utf-8"))["versionCode"])')
[ "$version" = "$json_version" ] || { printf 'VERSION_MISMATCH\n' >&2; exit 1; }
[ "$version_code" = "$json_version_code" ] || { printf 'VERSION_CODE_MISMATCH\n' >&2; exit 1; }
case "$("$PYTHON_BIN" -c 'import json; print(json.load(open("update.json", encoding="utf-8"))["changelog"])')" in
    http://*|https://*) ;;
    *) printf 'CHANGELOG_URL_NOT_HTTP(S)\n' >&2; exit 1 ;;
esac
grep -q "const APP_VERSION = '$version';" webroot/script.js
grep -q "const APP_VERSION_CODE = $version_code;" webroot/script.js
grep -q "RX_VERSION=\"$version\"" common.sh
grep -q "RX_VERSION_CODE=$version_code" common.sh
grep -q "RX_VERSION=\"$version\"" customize.sh
grep -q "$version" webroot/index.html
grep -q "$version" webroot/arm64-v8a/README.txt
grep -q "$version" native/rescuex_watchdog.c
grep -q "onboarding_ack" webroot/script.js
grep -q "module.prop is excluded" v351-safety.sh
[ ! -e module.prop.bak ] || { printf 'STALE_MODULE_PROP_BACKUP_PRESENT\n' >&2; exit 1; }
grep -q "const ONBOARDING_NOTICE_REVISION = 'r6';" webroot/script.js
grep -q 'versionChanged || noticeChanged' webroot/script.js
grep -q 'const ONBOARDING_COUNTDOWN_SECONDS = 8;' webroot/script.js
grep -q 'recommended' update.json
grep -q 'priority' update.json
grep -q 'updateMessage' update.json
grep -q 'id=\"cfg-watchdog-engine\"' webroot/index.html
grep -q 'watchdog-engine-choice' webroot/index.html
grep -q 'checked ? .native. : .shell.' webroot/script.js
grep -q 'WATCHDOG_ENGINE=${watchdogEngine}' webroot/script.js
grep -q 'sync_config_to_persist' common.sh
grep -q 'rx_config_repair_watchdog_engine' v351-safety.sh
grep -q 'preserve_watchdog_engine_choice' customize.sh
grep -q 'rescuex_data/config.conf' webroot/script.js
grep -q 'get_watchdog_engine_status' v351-safety.sh
grep -q 'ensure_watchdog_executable' v351-safety.sh
grep -q 'service_status_owned' service.sh
grep -q 'BOOT_TOKEN' common.sh
grep -q 'set_perm "$MODPATH/webroot/arm64-v8a/rescuex-watchdog" 0 0 0755' customize.sh
grep -q 'chmod 0755 "$MODPATH/webroot/arm64-v8a/rescuex-watchdog"' customize.sh
grep -q 'WATCHDOG_ENGINE=shell' customize.sh
grep -q "data-action=\"runIntegrityCheck\"" webroot/index.html
grep -q "'runIntegrityCheck'" webroot/script.js
grep -q 'data-action="v35RunSimulation"' webroot/index.html
grep -q "'v35RunSimulation'" webroot/script.js
grep -q 'v35_generate_diagnostic_bundle' features-v35.sh
grep -q 'ota_commit_build_baseline' service.sh
grep -q 'detect_ota_legacy' common.sh
grep -q 'ota-detection.sh' v351-safety.sh
grep -q 'integrity.sh' CONTRIBUTING.md

printf 'RELEASE CHECK PASSED: %s (%s)\n' "$version" "$version_code"
