#!/bin/bash
# gate: live
# inc-pt7h: AD_STON petrification clock, measured live.
# Loaded priest, forced natural-1 saves, one kobold on an open square adjacent
# to the player. ThrowDmg(EV_DAMAGE, AD_STON, ...) with EActor=player and
# EVictim=kobold reaches the AD_STON branch in src/Fight.cpp. The STONING
# status must last 20 units with cause SS_ATTK. Before the fix the Duration and
# Cause arguments were swapped, so the clock lasted SS_ATTK (6) units.
# FAIL, INCONCLUSIVE or missing results exit nonzero.
# fact: map layout and adjacent open square -- loaded fixture sav (tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav pins the dungeon), probe INCONCLUSIVE if none
# fact: victim save result -- LOFSetForcedSaveThrowRoll(1) forces a natural 1
# fact: victim identity and living type -- FIND("kobold"), fixed resource
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: RNG state -- none read; the clock is a constant
# Usage: tools/check_stoning_duration.sh
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

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-stoning-dur"
INCURSION_STONING_DUR_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. Is StoningDurProbe still called from Game::Play()?"
    exit 1
fi

lines="$(grep 'STONING_DUR_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no STONING_DUR_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"

if grep -qE 'STONING_DUR_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: the probe failed or was inconclusive."
    exit 1
fi
if ! grep -q 'STONING_DUR_PROBE: stoning=1 dur=20 cause=6 ' <<< "$lines"; then
    echo "FAIL: no measured line with stoning=1 dur=20 cause=6."
    exit 1
fi
if ! grep -q 'STONING_DUR_PROBE: PASS' <<< "$lines"; then
    echo "FAIL: missing PASS result."
    exit 1
fi

echo "PASS: AD_STON petrification lasts 20 units with cause SS_ATTK."
