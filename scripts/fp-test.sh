#!/usr/bin/env bash
# Run the native driver's capture example and ping the desktop at the exact
# moment the sensor is armed and waiting for a finger, so the tester does not
# have to watch the debug log to know when to touch it.
#
# Usage: scripts/fp-test.sh [seconds]   (default 60)
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/work/twd-libfprint/_build/examples/img-capture"
SECS="${1:-60}"
LOG="${FP_TEST_LOG:-/tmp/fp-test.log}"
OUT="${FP_TEST_PGM:-/tmp/fp-test.pgm}"

[ -x "$BIN" ] || { echo "build first: cd $REPO && ./setup.sh" >&2; exit 1; }
if pgrep -x fprintd >/dev/null; then
    echo "fprintd holds the device — stop it first (it exits on idle)" >&2
    exit 1
fi

: >"$LOG"
G_MESSAGES_DEBUG=all stdbuf -oL -eL timeout "$SECS" "$BIN" "$OUT" >"$LOG" 2>&1 &
CAP=$!

# Ping when the driver arms the device (FDT DOWN blocks until a real touch).
( tail -f --pid=$CAP "$LOG" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
    *"SWITCH TO FDT DOWN"*)
        notify-send -h string:x-canonical-private-synchronous:goodix-fp \
                    -a Fingerprint -u critical \
                    "👆 Place your finger" "sensor is armed and waiting" 2>/dev/null
        canberra-gtk-play -i message >/dev/null 2>&1 &
        printf '\n\033[1;33m>>> SENSOR ARMED — PLACE FINGER\033[0m\n'
        ;;
    *"Signal IMG Capture"*)
        notify-send -h string:x-canonical-private-synchronous:goodix-fp \
                    -a Fingerprint "✅ Image captured" "" 2>/dev/null
        canberra-gtk-play -i complete >/dev/null 2>&1 &
        printf '\033[1;32m<<< IMAGE CAPTURED\033[0m\n'
        ;;
    esac
done ) &
WATCH=$!

wait $CAP 2>/dev/null
kill $WATCH 2>/dev/null

echo
echo "=== thresholds learned from the sensor ==="
grep -E "FDT thresholds|FDT: reply" "$LOG" || echo "  (not learned)"
echo "=== cycle trace ==="
grep -E "SWITCH TO FDT|Finger-detect poll|Averaged|Signal IMG|written to|CRITICAL|failed to scan" "$LOG" | tail -20
[ -s "$OUT" ] && echo "=== image: $OUT ($(stat -c%s "$OUT") B) ==="
