#!/bin/bash
# Regression check for inc-32tj: a permanent field must survive a day change.
#
# Map::DaysPassed removes fields whose duration has run out (>= 1) and the -2
# "until the next day" sentinel. Upstream wrote the sentinel test as >= -2,
# which also matches -1, the PERMANENT sentinel, so every permanent field on
# the map was destroyed at the first day change.
#
# The fixture places a torch archon, whose light/aura field is permanent, then
# rests one night on the same map and counts the map's fields either side.
# See tools/keys/field-day-duration.keys for why depth 2, why an archon, why
# genocide first, and why the rest key is lowercase.
#
# Proved both ways on 2026-09-05, seed 20260905, binaries differing only in
# that one character:  fixed 1 -> 1,  unfixed 1 -> 0.
#
# Usage: tools/check_field_day_duration.sh (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BIN="${INCURSION_BIN:-./incursion-headless}"
KEYS=tools/keys/field-day-duration.keys
SEED=20260905

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_BIN="$BIN" tools/headless.sh "$KEYS" "$SEED" 2>&1)"
status=$?
run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
if [ "$status" -ne 0 ] || printf '%s\n' "$out" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: fixture exited $status. Run dir: ${run:-unknown}"
    printf '%s\n' "$out"
    exit 2
fi

read_count() {
    # $1 = screen label, $2 = row name. The counts live under
    # "-----THE CURRENT MAP-----" in the wizard resource-statistics dump.
    local f
    f="$(find "$run/logs/screens" -name "*-$1.txt" -print | head -1)"
    [ -n "$f" ] || return 1
    grep -oE "$2\.+[0-9]+" "$f" | head -1 | grep -oE '[0-9]+$'
}

before="$(read_count fields-before Fields)"
after="$(read_count fields-after Fields)"
crBefore="$(read_count fields-before Creatures)"
crAfter="$(read_count fields-after Creatures)"

[ -n "$before" ] && [ -n "$after" ] && [ -n "$crBefore" ] && [ -n "$crAfter" ] || {
    echo "INCONCLUSIVE: could not read both field counts. Run dir: $run"
    exit 2
}

echo "fields: before=$before after=$after   creatures: before=$crBefore after=$crAfter"

# The archon's own permanent field is the subject; one is all the fixture makes.
[ "$before" -ge 1 ] || {
    echo "INCONCLUSIVE: the fixture placed no permanent field to watch. Run dir: $run"
    exit 2
}

# Map::DaysPassed repopulates the level, so a rise in creatures is how this
# check knows the sweep actually ran rather than being skipped at its Day guard.
[ "$crAfter" -gt "$crBefore" ] || {
    echo "INCONCLUSIVE: the level did not repopulate, so DaysPassed never ran."
    echo "              Run dir: $run"
    exit 2
}

if [ "$after" -lt "$before" ]; then
    echo "FAIL: the day change destroyed $((before - after)) permanent field(s)."
    echo "      Run dir: $run"
    exit 1
fi

echo "PASS: the permanent field survived the day change."
