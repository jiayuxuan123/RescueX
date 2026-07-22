#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

required='META-INF/com/google/android/updater-script META-INF/com/google/android/update-binary module.prop customize.sh common.sh post-fs-data.sh service.sh watchdog.sh integrity.sh action.sh uninstall.sh webroot/index.html webroot/script.js webroot/style.css update.json'
for file in $required; do
    [ -e "$file" ] || { printf 'MISSING: %s\n' "$file" >&2; exit 1; }
done

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
grep -q "const APP_VERSION = '$version';" webroot/script.js
grep -q "const APP_VERSION_CODE = $version_code;" webroot/script.js
grep -q "data-action=\"runIntegrityCheck\"" webroot/index.html
grep -q "'runIntegrityCheck'" webroot/script.js
grep -q 'integrity.sh' CONTRIBUTING.md

printf 'RELEASE CHECK PASSED: %s (%s)\n' "$version" "$version_code"
