#!/bin/bash
# gate: live
# inc-jahch: fatigue comes back from an interrupted rest (max(25%, share slept)
# of the missing fatigue, at every level, never full), from waiting (1 point per
# 250 quiet turns, stopping at 50% of the maximum; with Fatigue Regeneration the
# old pace, stopping at 50% + 5% per rank) and from AutoRest (a character at or
# below 0 rests past 1000 calls until above 0).
#
# fact: character and its maximum fatigue -- fixture orc-barbarian-seed1-opt0822, INCURSION_LOAD; the probe reads Attr[A_FAT] itself and goes INCONCLUSIVE (red) under 6
# fact: fatigue before each case -- the probe sets cFP from the maximum
# fact: the encounter roll and the share slept -- forced by the probe through FatigueRestProbeArm (src/Player.cpp), not drawn
# fact: Fatigue Regeneration rank -- the probe sets Abilities[CA_FATIGUE_REGEN] and reads AbilityLevel back, INCONCLUSIVE (red) if it differs
# fact: a maximum fatigue of 1 -- the probe sets FatigueRestProbeMax, which CalcValues applies to the player (hunger and encumbrance bonuses cannot be relied on), reads Attr[A_FAT] back, INCONCLUSIVE (red) if it is not 1, and clears it afterward
# fact: quiet turns -- the probe sets FFCount to 0 and runs real Creature::DoTurn calls, no game clock
# fact: hunger -- the probe holds it at CONTENT (2870, no Hungry penalty to the maximum) every turn
# fact: mana and conditions that keep AutoRest going -- the probe zeroes uMana and hMana; the fixture starts with no timed condition
# fact: settings -- tools/fixtures/options-2026-08-22.dat, INCURSION_OPTIONS
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/fatigue-rest.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-fatigue_rest"
out="$(INCURSION_FATIGUE_REST_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run_status=$?

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "$out" | tail -20
    echo "FAIL: no $log. The probe never wrote anything."
    exit 1
fi

lines="$(grep 'FATREST_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no FATREST_PROBE lines."
    exit 1
fi
echo "$lines"
echo "Specimen: $log"
if [ "$run_status" -ne 0 ]; then
    echo "$out" | tail -20
    echo "FAIL: headless exited $run_status"
    exit 1
fi

if grep -qE 'FATREST_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
for marker in rest-vigorous-10 rest-vigorous-25 rest-vigorous-60 rest-vigorous-90 \
    rest-fatigued-10 rest-fatigued-25 rest-fatigued-60 rest-fatigued-90 \
    rest-exhausted-10 rest-exhausted-25 rest-exhausted-60 rest-exhausted-90 \
    rest-vigorous-100 wait-rank0 wait-at-ceiling-rank0 wait-rank1 wait-rank10 \
    autorest-rank0 autorest-rank10 autorest-rank1 wait-max1 autorest-max1; do
    if ! grep -qE "FATREST_PROBE: $marker .* PASS" <<< "$lines"; then
        echo "FAIL: missing PASS for $marker"
        exit 1
    fi
done
if ! grep -qE 'FATREST_PROBE: done failures=0' <<< "$lines"; then
    echo "FAIL: probe did not finish with failures=0"
    exit 1
fi

echo "PASS: an interrupted rest, waiting and AutoRest restore fatigue as ruled."
