#!/system/bin/sh

MODDIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
[ -f "$MODDIR/common.sh" ] || exit 1
. "$MODDIR/common.sh"
cleanup_integrity() {
    local current
    current=$(cat "$INTEGRITY_PID_FILE" 2>/dev/null)
    [ "$current" = "$$" ] && rm -f "$INTEGRITY_PID_FILE"
    rmdir "$STATE_DIR/.integrity_start.lock" 2>/dev/null
    exit 0
}
trap cleanup_integrity TERM INT EXIT
read_config
[ "$INTEGRITY_CHECK_ENABLED" = "true" ] || exit 0

echo $$ > "$INTEGRITY_PID_FILE"
chmod 0600 "$INTEGRITY_PID_FILE" 2>/dev/null

integrity_check_once
while :; do
    random_value=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ')
    case "$random_value" in ''|*[!0-9]*) random_value=$(get_uptime_sec) ;; esac
    interval=$((INTEGRITY_INTERVAL_MIN_SEC + random_value % INTEGRITY_INTERVAL_MIN_SEC))
    sleep "$interval"
    read_config
    [ "$INTEGRITY_CHECK_ENABLED" = "true" ] || exit 0
    integrity_check_once
done
