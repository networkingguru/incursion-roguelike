#!/bin/bash
# Regression check for inc-nhrk: carried light participates in all shadow-hide
# gates. The fixture begins hidden, equips a lit torch, moves to trigger reveal,
# then attempts manual Hide and must receive the carried-light refusal.
# Usage: tools/check_hide_carried_light.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/hide-carried-light.keys 1 2>&1)"
status=$?
RUN="$(echo "$out" | awk '/^run:/ {print $2}')"

[ "$status" -eq 0 ] || {
    echo "INCONCLUSIVE: headless fixture exited $status. Run dir: $RUN"
    echo "$out"
    exit 2
}

equipped="$(ls "$RUN"/logs/screens/*torch-equipped-hidden* 2>/dev/null | head -1)"
after_move="$(ls "$RUN"/logs/screens/*after-move* 2>/dev/null | head -1)"
refused="$(ls "$RUN"/logs/screens/*hide-refused* 2>/dev/null | head -1)"
[ -f "$equipped" ] && [ -f "$after_move" ] && [ -f "$refused" ] || {
    echo "INCONCLUSIVE: fixture wrote no equipped/move/refusal dump. Run dir: $RUN"
    exit 2
}

grep -qi 'Light Source *:torch' "$equipped" || {
    echo "INCONCLUSIVE: torch was not equipped in the Light Source slot. Run dir: $RUN"
    exit 2
}
grep -q 'Hiding' "$equipped" || {
    echo "INCONCLUSIVE: rogue was not hidden when the torch was equipped. Run dir: $RUN"
    exit 2
}

fail=0
if grep -q 'Hiding' "$after_move"; then
    echo "FAIL: rogue remained Hiding after moving with the equipped lit torch."
    fail=1
fi
if ! grep -qi 'carrying a light' "$refused"; then
    echo "FAIL: manual Hide did not print the carried-light refusal."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: equipped lit torch was verified; moving cleared Hiding, and manual Hide"
    echo "      was refused with the carried-light message. Run dir: $RUN"
    exit 0
fi
echo "      Run dir: $RUN"
exit 1
