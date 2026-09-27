#!/bin/bash
# gate: live
# inc-p0h1: the SRD three-curse Bestow Curse redesign -- a player-cast menu
# ESC cannot escape, random picks for every other source, the
# ability/misfortune/hesitation curses themselves (hesitation rolling once
# per game tick at one standard action's cost), Remove Curse vs Dispel
# Magic, and duplicate refusal.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/dive.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-bestow"
out="$(INCURSION_BESTOW_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run_status=$?

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. The probe never wrote anything -- is"
    echo "      BestowProbe still called from Game::Play()?"
    exit 1
fi

# errors.log timestamps every line and prints a one-time call stack after a
# message's first occurrence (tools/headless.sh convention), so match the
# marker as a substring, not an anchor.
lines="$(grep 'BESTOW_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no BESTOW_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"
if [ "$run_status" -ne 0 ]; then
    echo "$out"
    echo "FAIL: headless exited $run_status"
    exit 1
fi

# Here-strings avoid the pipe/SIGPIPE false-negative described in inc-wbq9.
if grep -qE 'BESTOW_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
for marker in \
    'menu-ability calls=2 int=1 mag=-6 PASS' \
    'menu-ability present=1 PASS' \
    'menu-misfortune present=1 PASS' \
    'menu-hesitation present=1 PASS' \
    'esc-safety keysLeft=0 str=1 mag=-6 PASS' \
    'trap-random menuCalls=0 a=[0-9]+ m=[0-9]+ h=[0-9]+ PASS' \
    'monster-random menuCalls=0 a=[0-9]+ m=[0-9]+ h=[0-9]+ PASS' \
    'ability-floor before=6 mag=-6 after=1 PASS' \
    'misfortune hit=-4 sav=-4,-4,-4 skill=-4 ac=0 PASS' \
    'hesitate-player lost=[0-9]+ runs=200 pct=[0-9]+ PASS' \
    'hesitate-player-once-per-tick rolls=200 ticks=200 extraCalls=[0-9]+ extraRolls=0 PASS' \
    'hesitate-player-time cost=[0-9]+ stdCost=[0-9]+ timepct=[0-9]+ PASS' \
    'hesitate-monster lost=[0-9]+ runs=200 pct=[0-9]+ PASS' \
    'hesitate-monster-once-per-tick rolls=200 ticks=200 extraCalls=[0-9]+ extraRolls=0 PASS' \
    'hesitate-monster-time cost=[0-9]+ stdCost=[0-9]+ timepct=[0-9]+ PASS' \
    'remove-curse cleared=1 PASS' \
    'repeat-curse first=1 second=1 PASS' \
    'dispel-keeps curse=1 PASS' \
    ; do
    if ! grep -qE "BESTOW_PROBE: $marker$" <<< "$lines"; then
        echo "FAIL: missing result $marker"
        exit 1
    fi
done

# The hesitation share (both by action count and by time) must land inside
# the spec's 35%-65% band, read straight from the logged pct=/timepct=, not
# re-derived from lost/runs.
for who in player monster; do
    pct="$(grep -oE "hesitate-$who lost=[0-9]+ runs=200 pct=[0-9]+" <<< "$lines" \
        | grep -oE 'pct=[0-9]+' | grep -oE '[0-9]+')"
    if [ -z "$pct" ] || [ "$pct" -lt 35 ] || [ "$pct" -gt 65 ]; then
        echo "FAIL: hesitate-$who pct=$pct outside 35-65"
        exit 1
    fi
    timepct="$(grep -oE "hesitate-$who-time cost=[0-9]+ stdCost=[0-9]+ timepct=[0-9]+" <<< "$lines" \
        | grep -oE 'timepct=[0-9]+' | grep -oE '[0-9]+')"
    if [ -z "$timepct" ] || [ "$timepct" -lt 35 ] || [ "$timepct" -gt 65 ]; then
        echo "FAIL: hesitate-$who-time timepct=$timepct outside 35-65"
        exit 1
    fi
done

echo "PASS: menu choice honoured for a player, ESC cancels neither menu," \
    "random with no menu for every other source, ability/misfortune/" \
    "hesitation curses each measured correctly, hesitation rolls once per" \
    "game tick at one standard action's cost, Remove Curse clears all" \
    "three, Dispel Magic clears none, and a repeated curse does nothing."
