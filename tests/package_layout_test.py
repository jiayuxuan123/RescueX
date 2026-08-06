#!/usr/bin/env python3
"""Validate the generated RescueX flashable ZIP without Android tooling."""
from __future__ import annotations

import hashlib
import sys
import zipfile
from pathlib import PurePosixPath

if len(sys.argv) != 2:
    raise SystemExit("usage: package_layout_test.py <RescueX.zip>")

archive_path = sys.argv[1]
required = {
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
    "module.prop",
    "customize.sh",
    "post-fs-data.sh",
    "service.sh",
    "uninstall.sh",
    "action.sh",
    "common.sh",
    "watchdog.sh",
    "integrity.sh",
    "features-v35.sh",
    "v351-safety.sh",
    "webroot/index.html",
    "webroot/script.js",
    "webroot/style.css",
    "webroot/workspace-v2.css",
    "webroot/arm64-v8a/rescuex-watchdog",
}
# Runtime state can contain device-specific logs, module inventories and
# transaction journals. A flashable release must always start with clean state.
forbidden_prefixes = (
    ".git/",
    ".reasonix/",
    "tests/",
    "__pycache__/",
    "webroot/state/",
)

with zipfile.ZipFile(archive_path) as archive:
    names = set(archive.namelist())
    missing = sorted(required - names)
    if missing:
        raise SystemExit(f"missing required package entries: {', '.join(missing)}")

    for name in names:
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"unsafe archive entry: {name}")
        if name.startswith(forbidden_prefixes):
            raise SystemExit(f"development-only entry in package: {name}")

    module_prop = archive.read("module.prop").decode("utf-8")
    props = dict(line.split("=", 1) for line in module_prop.splitlines() if "=" in line)
    if props.get("id") != "RescueX":
        raise SystemExit("module.prop id must be RescueX")
    if not props.get("version") or not props.get("versionCode", "").isdigit():
        raise SystemExit("module.prop must include version and numeric versionCode")

    watchdog_info = archive.getinfo("webroot/arm64-v8a/rescuex-watchdog")
    if watchdog_info.file_size == 0:
        raise SystemExit("native watchdog must not be empty")

with open(archive_path, "rb") as package:
    digest = hashlib.sha256(package.read()).hexdigest()
print(f"package layout verified: {archive_path}")
print(f"sha256={digest}")
