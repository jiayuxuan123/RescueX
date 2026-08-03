#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

required='META-INF/com/google/android/updater-script META-INF/com/google/android/update-binary module.prop customize.sh common.sh features-v35.sh post-fs-data.sh service.sh watchdog.sh integrity.sh action.sh uninstall.sh webroot/index.html webroot/script.js webroot/style.css update.json'
for file in $required; do
    [ -e "$file" ] || { printf 'MISSING: %s\n' "$file" >&2; exit 1; }
done

[ -x webroot/arm64-v8a/rescuex-watchdog ] || { printf 'NATIVE_WATCHDOG_MISSING_OR_NOT_EXECUTABLE\n' >&2; exit 1; }
file webroot/arm64-v8a/rescuex-watchdog | grep -Eq 'AArch64|arm64' || { printf 'NATIVE_WATCHDOG_NOT_AARCH64\n' >&2; exit 1; }
readelf -l webroot/arm64-v8a/rescuex-watchdog | grep -q '/system/bin/linker64' || { printf 'NATIVE_WATCHDOG_NOT_ANDROID_PIE\n' >&2; exit 1; }

for file in *.sh; do
    sh -n "$file"
done
node --check webroot/script.js
python3 -m json.tool update.json >/dev/null

version=$(awk -F= '$1 == "version" { print $2; exit }' module.prop)
version_code=$(awk -F= '$1 == "versionCode" { print $2; exit }' module.prop)
json_version=$(python3 -c 'import json; print(json.load(open("update.json"))["version"])')
json_version_code=$(python3 -c 'import json; print(json.load(open("update.json"))["versionCode"])')
[ "$version" = "$json_version" ] || { printf 'VERSION_MISMATCH\n' >&2; exit 1; }
[ "$version_code" = "$json_version_code" ] || { printf 'VERSION_CODE_MISMATCH\n' >&2; exit 1; }
case "$(python3 -c 'import json; print(json.load(open("update.json"))["changelog"])')" in
    http://*|https://*) ;;
    *) printf 'CHANGELOG_URL_NOT_HTTP(S)\n' >&2; exit 1 ;;
esac
grep -q "const APP_VERSION = '$version';" webroot/script.js
grep -q "const APP_VERSION_CODE = $version_code;" webroot/script.js
grep -q "RX_VERSION=\"$version\"" common.sh
grep -q "RX_VERSION_CODE=$version_code" common.sh
grep -q "onboarding_ack" webroot/script.js
grep -q "module.prop is excluded" v351-safety.sh
[ ! -e module.prop.bak ] || { printf 'STALE_MODULE_PROP_BACKUP_PRESENT\n' >&2; exit 1; }
grep -q "const ONBOARDING_NOTICE_REVISION = 'r3';" webroot/script.js
grep -q 'versionChanged && noticeChanged' webroot/script.js
grep -q 'id=\"cfg-watchdog-engine\"' webroot/index.html
grep -q 'watchdog-engine-choice' webroot/index.html
grep -q 'checked ? .native. : .shell.' webroot/script.js
grep -q 'WATCHDOG_ENGINE=${watchdogEngine}' webroot/script.js
grep -q 'sync_config_to_persist' common.sh
grep -q 'rx_config_repair_watchdog_engine' v351-safety.sh
grep -q 'preserve_watchdog_engine_choice' customize.sh
grep -q 'rescuex_data/config.conf' webroot/script.js
grep -q 'get_watchdog_engine_status' v351-safety.sh
grep -q 'WATCHDOG_ENGINE=shell' customize.sh
grep -q "data-action=\"runIntegrityCheck\"" webroot/index.html
grep -q "'runIntegrityCheck'" webroot/script.js
grep -q 'data-action="v35RunSimulation"' webroot/index.html
grep -q "'v35RunSimulation'" webroot/script.js
grep -q 'v35_generate_diagnostic_bundle' features-v35.sh
grep -q 'integrity.sh' CONTRIBUTING.md

printf 'RELEASE CHECK PASSED: %s (%s)\n' "$version" "$version_code"
