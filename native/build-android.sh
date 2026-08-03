#!/usr/bin/env sh
# Build the optional RescueX native watchdog for Android arm64-v8a.
# Usage: ANDROID_NDK_HOME=/path/to/android-ndk ./native/build-android.sh
# The binary is intentionally optional: without it RescueX remains on the
# audited Shell watchdog path. Do not substitute a GNU/Linux cross build.
set -eu
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to an Android NDK r26+ directory}"
HOST_TAG=${HOST_TAG:-linux-x86_64}
API=${ANDROID_API:-26}
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/bin"
CC="$TOOLCHAIN/aarch64-linux-android${API}-clang"
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/rescuex_watchdog.c"
OUT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/webroot/arm64-v8a/rescuex-watchdog"
[ -x "$CC" ] || { echo "Android clang missing: $CC" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"
"$CC" -std=c11 -O2 -fPIE -pie -fstack-protector-strong -D_FORTIFY_SOURCE=2 \
  -Wall -Wextra -Werror -Wl,-z,relro,-z,now -o "$OUT" "$SRC"
chmod 0755 "$OUT"
"$OUT" --self-test
echo "Built $OUT"
