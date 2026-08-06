#!/usr/bin/env sh
# Cross-root transaction regression: same module ID must restore only its owned marker.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
MODDIR="$ROOT" RESCUEX_PERSIST_DIR="$TMP/persist" . "$ROOT/common.sh"
_rescuex_init_paths
STATE_DIR="$TMP/state"; PERSIST_DIR="$TMP/persist"; RESCUE_TXN_DIR="$PERSIST_DIR/rescue-transactions"; RESCUED_DISABLED_LIST="$STATE_DIR/rescued_disabled.list"
MODULE_BASE="$TMP/magisk"; MODULE_BASE_KSU="$TMP/ksu"; MODULE_BASE_AP="$TMP/ap"
SELF_ID=RescueX; DRY_RUN=false; mkdir -p "$STATE_DIR" "$MODULE_BASE/duplicate" "$MODULE_BASE_KSU/duplicate" "$RESCUE_TXN_DIR"
: > "$MODULE_BASE_KSU/duplicate/disable"
rescue_transaction_begin_targets test || exit 1
rescue_transaction_disable_target MAGISK "$MODULE_BASE" duplicate "$MODULE_BASE/duplicate" || exit 1
[ -f "$MODULE_BASE/duplicate/disable" ]
rescue_transaction_restore_current || exit 1
[ ! -f "$MODULE_BASE/duplicate/disable" ]
[ -f "$MODULE_BASE_KSU/duplicate/disable" ]
# A partial restore persists completed targets, so a later retry only restores
# the target whose module path became available again.
mkdir -p "$MODULE_BASE/retry-a" "$MODULE_BASE/retry-b"
rescue_transaction_begin_targets retry || exit 1
rescue_transaction_disable_target MAGISK "$MODULE_BASE" retry-a "$MODULE_BASE/retry-a" || exit 1
rescue_transaction_disable_target MAGISK "$MODULE_BASE" retry-b "$MODULE_BASE/retry-b" || exit 1
rescue_transaction_finish_targets || exit 1
rm -rf "$MODULE_BASE/retry-b"
if rescue_transaction_restore_current; then exit 1; fi
[ ! -f "$MODULE_BASE/retry-a/disable" ]
grep -q 'MODULE_ID=retry-a.*STATE=RESTORED' "$RESCUE_TRANSACTION_PATH/targets"
mkdir -p "$MODULE_BASE/retry-b"; : > "$MODULE_BASE/retry-b/disable"
rescue_transaction_restore_current || exit 1
[ ! -f "$MODULE_BASE/retry-b/disable" ]
# A forged journal root must fail closed and preserve every marker.
mkdir -p "$MODULE_BASE/forged"; : > "$MODULE_BASE/forged/disable"
rescue_transaction_begin_targets forged || exit 1
printf 'MANAGER=MAGISK|BASE=/tmp/forged|MODULE_ID=forged|PATH=/tmp/forged/forged|MARKER=/tmp/forged/forged/disable|SHADOW=-|PREEXISTING=0\n' > "$RESCUE_TRANSACTION_PATH/targets"
if rescue_transaction_restore_current; then exit 1; fi
[ -f "$MODULE_BASE/forged/disable" ]
printf 'cross-root rescue transaction test passed\n'
