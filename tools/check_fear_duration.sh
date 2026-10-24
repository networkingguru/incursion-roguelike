#!/bin/bash
# gate: live
# inc-4hk3: AD_FEAR fear duration, measured live.
# Loaded priest, forced natural-1 saves, one kobold on an open square adjacent
# to the player. ThrowDmg(EV_DAMAGE, AD_FEAR, ...) with EActor=player and
# EVictim=kobold reaches the AD_FEAR branch in src/Fight.cpp. The AFRAID status
# must last the amount converted from rounds to two-round units, with cause
# SS_ATTK and val FEAR_MAGIC. Before the fix the Duration and Cause arguments
# were swapped, so the fear lasts SS_ATTK (6) units and carries the roll as its cause.
# FAIL, INCONCLUSIVE or missing results exit nonzero.
# fact: map layout and adjacent open square -- loaded fixture sav (tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav pins the dungeon), probe INCONCLUSIVE if none
# fact: victim save result -- LOFSetForcedSaveThrowRoll(1) forces a natural 1
# fact: victim identity and living type -- FIND("kobold"), fixed resource
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: RNG state -- none read; the amounts 3 and 9 are passed in
# Usage: tools/check_fear_duration.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/bane-radius.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-fear-dur"
INCURSION_FEAR_DUR_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. Is FearDurProbe still called from Game::Play()?"
    exit 1
fi

lines="$(grep 'FEAR_DUR_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no FEAR_DUR_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"

if grep -qE 'FEAR_DUR_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: the probe failed or was inconclusive."
    exit 1
fi
if ! grep -q 'FEAR_DUR_PROBE: PASS' <<< "$lines"; then
    echo "FAIL: missing PASS result."
    exit 1
fi

echo "PASS: AD_FEAR fear lasts the rounds amount with cause SS_ATTK and val FEAR_MAGIC."
