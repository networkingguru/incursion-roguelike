#!/bin/bash
# gate: live
# inc-b0ziu.2: wizard "Wake Every Creature" leaves no sleeping creature on the level.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: a creature exists on the map -- wizard Monster Summoning (tools/keys/wake-all.keys)
# fact: that creature is asleep -- INCURSION_WAKE_PROBE=1 puts every creature to sleep first
# fact: settings -- tools/fixtures/options-2026-08-22.dat
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/wake-all.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-wake-all"
INCURSION_WAKE_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
line="$(grep 'WAKE_PROBE:' "$log" 2>/dev/null | tail -1)"
if [ -z "$line" ]; then
    echo "FAIL: no WAKE_PROBE line in $log (command never ran, or probe removed)."
    exit 1
fi
echo "$line"
echo "Specimen: $log"

before="$(sed -n 's/.*before=\([0-9]*\).*/\1/p' <<< "$line")"
after="$(sed -n 's/.*after=\([0-9]*\).*/\1/p' <<< "$line")"
if [ -z "$before" ] || [ "$before" -eq 0 ]; then
    echo "FAIL: no sleeping creature before the command (before=$before)."
    exit 1
fi
if [ "$after" != "0" ]; then
    echo "FAIL: $after creatures still asleep after the command."
    exit 1
fi
echo "PASS: $before sleeping creatures before, 0 after."
