#!/usr/bin/env bash
# Cross-finger stress test for the Goodix 55a4 driver.
#
# fprintd's CLI cannot report *which* finger matched, but verifying against a
# NAMED finger gives the same information in its security-relevant form:
#   press A, verify against A  -> must MATCH      (true accept)
#   press A, verify against B  -> must NOT match  (false accept between two
#                                                  enrolled fingers of the same
#                                                  hand — the hardest impostor
#                                                  case there is)
#
# Prompts are mirrored to desktop notifications, because the tester follows
# the popups rather than the terminal.
#
# Usage: scripts/fp-stress.sh [rounds]      (default 3 -> 12 presses)
#
# Both fingers must already be enrolled:
#   fprintd-enroll -f right-index-finger
#   fprintd-enroll -f right-thumb
set -u
ROUNDS="${1:-3}"
A="right-thumb"
B="right-index-finger"

# Without this check the run is worse than useless: fprintd-verify against a
# finger that was never enrolled exits immediately, which scores as a miss on
# the match trials and as a correct rejection on the impostor trials — half the
# results invented, without the sensor ever being touched.
enrolled="$(fprintd-list "$USER" 2>/dev/null || true)"
for f in "$A" "$B"; do
    case "$enrolled" in
    *"$f"*) ;;
    *)  echo "'$f' is not enrolled — enrol it first:" >&2
        echo "   fprintd-enroll -f $f" >&2
        exit 1 ;;
    esac
done

finger_label() {
    case "$1" in
    right-thumb)        echo "THUMB" ;;
    right-index-finger) echo "INDEX" ;;
    *)                  echo "$1" ;;
    esac
}

pop() {  # pop <urgency> <title> <body>
    # No fixed --replace-id here: once the user dismisses a notification with a
    # given id, KDE stops displaying later updates carrying that same id, and
    # the prompts silently vanish mid-run. A short expiry keeps them from
    # piling up instead.
    notify-send -t 4000 -u "$1" -a "Fingerprint" "$2" "$3" 2>/dev/null
}


declare -i tp=0 fn=0 tn=0 fp=0 n=0
TOTAL=$((ROUNDS * 4))

trial() {  # trial <press> <verify_against> <expect: match|nomatch>
    local press="$1" against="$2" expect="$3" out result pn an hint
    pn="$(finger_label "$press")"; an="$(finger_label "$against")"
    n+=1
    if [ "$expect" = match ]; then hint="must MATCH"; else hint="must REJECT"; fi

    pop critical "👆 Place: $pn finger" "trial $n of $TOTAL · verify against \"$an\" · $hint"
    canberra-gtk-play -i message >/dev/null 2>&1 &
    printf '\n\033[1;33m>>> PLACE: %s FINGER\033[0m  (trial %d/%d, verify against "%s", %s)\n' \
        "$pn" "$n" "$TOTAL" "$an" "$hint"

    out="$(stdbuf -oL timeout 40 fprintd-verify -f "$against" 2>&1)"
    if grep -q "verify-match" <<<"$out"; then result=match; else result=nomatch; fi
    # Give the plate time to clear before the next trial re-activates the device
    # and captures a fresh background: a finger still on (or just coming off)
    # the sensor would otherwise be baked into that background.
    sleep 1.5

    if [ "$result" = "$expect" ]; then
        if [ "$expect" = match ]; then tp+=1; else tn+=1; fi
        printf '\033[1;32m<<< CORRECT\033[0m\n'
        pop normal "✅ Correct" "trial $n of $TOTAL"
        canberra-gtk-play -i complete >/dev/null 2>&1 &
    else
        if [ "$expect" = match ]; then fn+=1; else fp+=1; fi
        if [ "$expect" = match ]; then
            printf '\033[1;31m<<< MISS — enrolled finger not recognised\033[0m\n'
            pop critical "❌ Miss" "enrolled finger not recognised ($n of $TOTAL)"
        else
            printf '\033[1;31m<<< FALSE ACCEPT — impostor accepted!\033[0m\n'
            pop critical "❌ FALSE ACCEPT" "impostor accepted! ($n of $TOTAL)"
        fi
        canberra-gtk-play -i dialog-error >/dev/null 2>&1 &
    fi
}

for ((r = 1; r <= ROUNDS; r++)); do
    printf '\n\033[1m===== round %d of %d =====\033[0m\n' "$r" "$ROUNDS"
    trial "$A" "$A" match      # enrolled finger against its own template
    trial "$A" "$B" nomatch    # wrong template — must be rejected
    trial "$B" "$B" match
    trial "$B" "$A" nomatch
done

printf '\n\033[1m================ RESULT ================\033[0m\n'
printf '  enrolled finger correctly accepted       : %d\n' "$tp"
printf '  enrolled finger MISSED : %d\n' "$fn"
printf '  impostor correctly rejected   : %d\n' "$tn"
printf '  FALSE ACCEPTS      : %d\n' "$fp"
printf '  ---\n'
printf '  true accept rate             : %d%%\n' $(( tp * 100 / (tp + fn == 0 ? 1 : tp + fn) ))
printf '  false accept rate           : %d%%\n' $(( fp * 100 / (tn + fp == 0 ? 1 : tn + fp) ))
pop normal "Stress test finished" "true accept: $tp of $((tp+fn)) · false accepts: $fp of $((tn+fp))"
