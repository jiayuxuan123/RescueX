#!/usr/bin/env sh
# Build the optional RescueX native watchdog for Android arm64-v8a.
# Preferred: ANDROID_NDK_HOME=/path/to/android-ndk ./native/build-android.sh
# On an arm64 Linux host without a native Android NDK toolchain, set
# RESCUEX_CC to an Android clang wrapper (or use an external NDK build host).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/native/rescuex_watchdog.c"
OUT="$ROOT/webroot/arm64-v8a/rescuex-watchdog"
API=${ANDROID_API:-26}
HOST_TAG=${HOST_TAG:-linux-x86_64}

if [ -n "${RESCUEX_CC:-}" ]; then
    CC="$RESCUEX_CC"
elif [ -n "${ANDROID_NDK_HOME:-}" ]; then
    CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/bin/aarch64-linux-android${API}-clang"
else
    echo "Set ANDROID_NDK_HOME or RESCUEX_CC; a GNU/Linux glibc build is not accepted." >&2
    exit 2
fi

[ -x "$CC" ] || { echo "Android clang missing: $CC" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"
"$CC" -std=c11 -O2 -fPIE -pie -fstack-protector-strong -D_FORTIFY_SOURCE=2 \
  -Wall -Wextra -Werror -Wl,-z,relro,-z,now -o "$OUT" "$SRC"
chmod 0755 "$OUT"
"$OUT" --self-test
echo "Built $OUT"
