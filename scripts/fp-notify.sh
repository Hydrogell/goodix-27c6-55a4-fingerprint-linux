#!/usr/bin/env bash
# Visible sensor-state indicator for the Goodix 55a4.
#
# The LED in the power button is switched by the sensor itself, via command 0xae
# (see docs/PROTOCOL.md), and the driver drives it for the lifetime of an open
# device. This script is not a substitute for that light: it adds desktop popups
# and a sound so a tester knows when to place a finger and what the result was
# without watching the terminal.
#
# Usage:
#   scripts/fp-notify.sh verify        # one verify, with prompts
#   scripts/fp-notify.sh verify 5      # five verifies in a row
#   scripts/fp-notify.sh enroll        # full enrollment, prompts every stage
#
# No root needed.
set -u

MODE="${1:-verify}"
COUNT="${2:-1}"
SYNC_HINT=(-h string:x-canonical-private-synchronous:goodix-fp)

note() {  # note <urgency> <title> <body>
    # No replace-id / sync hint: KDE stops displaying updates that reuse an id
    # the user has already dismissed, and the prompts silently vanish mid-run.
    notify-send -t 4000 -u "$1" -a "Fingerprint" "$2" "$3" 2>/dev/null
}
ding() { canberra-gtk-play -i "$1" >/dev/null 2>&1 & }

touch_now() {
    note normal "👆 Place your finger" "$1"
    ding message
    printf '\n\033[1;33m>>> PLACE FINGER  —  %s\033[0m\n' "$1"
}
ok_msg() {
    note normal "✅ Match" "$1"
    ding complete
    printf '\033[1;32m<<< MATCH  %s\033[0m\n' "$1"
}
bad_msg() {
    note critical "❌ No match" "$1"
    ding dialog-error
    printf '\033[1;31m<<< NO MATCH  %s\033[0m\n' "$1"
}

run_verify() {
    local n="$1" i
    for ((i = 1; i <= n; i++)); do
        touch_now "check $i of $n"
        # shellcheck disable=SC2034
        while IFS= read -r line; do
            case "$line" in
            *verify-match*)    ok_msg  "($i/$n)" ;;
            *verify-no-match*) bad_msg "($i/$n) — press firmly, centred" ;;
            *verify-retry*|*Verify\ result*retry*)
                note normal "↻ Again" "the finger did not land cleanly"; ding message ;;
            esac
        done < <(stdbuf -oL timeout 40 fprintd-verify 2>&1)
    done
    note low "Done" "verifications done: $n"
}

# Impostor / false-accept run: press fingers that are NOT enrolled. Here a
# rejection is the CORRECT outcome, so the feedback is inverted — otherwise the
# tester is told "press harder" for exactly the result we want.
run_impostor() {
    local n="$1" i good=0 bad=0
    for ((i = 1; i <= n; i++)); do
        note normal "👆 IMPOSTOR finger $i of $n" "place a finger that is NOT enrolled"
        ding message
        printf '\n\033[1;36m>>> PLACE AN IMPOSTOR (NOT enrolled) FINGER — %d of %d\033[0m\n' "$i" "$n"
        while IFS= read -r line; do
            case "$line" in
            *verify-no-match*)
                good=$((good + 1))
                note normal "✅ Rejected (correct)" "$i/$n"
                ding complete
                printf '\033[1;32m<<< REJECTED — correct (%d/%d)\033[0m\n' "$i" "$n"
                ;;
            *verify-match*)
                bad=$((bad + 1))
                note critical "❌ FALSE ACCEPT" "an impostor finger was accepted! ($i/$n)"
                ding dialog-error
                printf '\033[1;31m<<< FALSE ACCEPT — impostor was ACCEPTED (%d/%d)\033[0m\n' "$i" "$n"
                ;;
            esac
        done < <(stdbuf -oL timeout 40 fprintd-verify -f any 2>&1)
        # let the plate clear before the next activation captures a background
        sleep 1.5
    done
    printf '\n\033[1mRESULT: correctly rejected %d, false accepts %d of %d\033[0m\n' "$good" "$bad" "$n"
    note low "Impostor run finished" "false accepts: $bad of $n"
}

run_enroll() {
    local finger="${1:-}" stage=0 label
    label="${finger:-default finger}"
    touch_now "enrolment [$label]: touch 1"
    while IFS= read -r line; do
        case "$line" in
        *enroll-stage-passed*)
            stage=$((stage + 1))
            touch_now "enrolment [$label]: touch $((stage + 1)) (accepted: $stage)"
            ;;
        *enroll-completed*)
            note normal "✅ Enrolment complete" "finger stored"
            ding complete
            printf '\033[1;32m<<< ENROLMENT COMPLETE\033[0m\n'
            ;;
        *enroll-failed*|*enroll-duplicate*)
            bad_msg "enrolment failed"
            ;;
        *retry*|*remove-and-retry*)
            note normal "↻ Again" "lift your finger and place it again"; ding message
            ;;
        esac
    done < <(stdbuf -oL timeout 300 fprintd-enroll ${finger:+-f "$finger"} 2>&1)
}

case "$MODE" in
verify) run_verify "$COUNT" ;;
impostor) run_impostor "$COUNT" ;;
enroll) run_enroll "${2:-}" ;;
*) echo "usage: $0 {verify [N] | impostor [N] | enroll [finger]}" >&2; exit 2 ;;
esac
