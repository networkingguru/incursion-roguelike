#!/bin/bash
# gate: live
# inc-93mxz: LoseFatigue recalculates on every fatigue band change, so Strength
# and the fatigue floor the pass-out warning reads equal a fresh CalcValues,
# including the payment from exactly 0 to below 0 (Fine to Fatigued).
#
# fact: character and its floor -- fixture orc-barbarian-seed1-opt0822, INCURSION_LOAD; the probe reads Attr[A_FAT] itself and goes INCONCLUSIVE (red) under 4
# fact: fatigue before each payment -- the probe sets cFP exactly (0, -1), no seed draws it
# fact: the payment -- the probe calls the real Creature::LoseFatigue(n,false) itself
# fact: the load -- the probe adds apples (lib food, fixed weight) one at a time until the load is EN_LIGHT at fatigue 0 and EN_MODERATE Fatigued, INCONCLUSIVE (red) if none in 400
# fact: the expected floor and the warning payment -- the probe settles CalcValues 4 times at each fatigue (a fresh floor) and compares with the floor after real LoseFatigue payments
# fact: stable floor -- the probe calls CalcValues 3 times at one fatigue and requires equal floors (cross-floor, above-zero)
# fact: the expected Strength and floor -- the probe reads a fresh CalcValues of the same character, not a constant
# fact: the seed -- changes nothing the probe reads; two seeds (1, 2) run to show that
# fact: settings -- tools/fixtures/options-2026-08-22.dat, INCURSION_OPTIONS
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/fatigue-floor.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

rc=0
for SEED in 1 2; do
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-fatigue_floor-$SEED"
    out="$(INCURSION_FATIGUE_FLOOR_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
        INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
        tools/headless.sh "$KEYS" "$SEED" 2>&1)"
    run_status=$?

    log="$RUN_DIR/logs/errors.log"
    if [ ! -s "$log" ]; then
        echo "$out" | tail -20
        echo "FAIL: seed $SEED: no $log. The probe never wrote anything."
        exit 1
    fi
    lines="$(grep 'FATFLOOR_PROBE:' "$log")"
    if [ -z "$lines" ]; then
        echo "FAIL: seed $SEED: $log has no FATFLOOR_PROBE lines."
        exit 1
    fi
    echo "seed $SEED:"
    echo "$lines"
    echo "Specimen: $log"
    if [ "$run_status" -ne 0 ]; then
        echo "$out" | tail -20
        echo "FAIL: seed $SEED: headless exited $run_status"
        exit 1
    fi
    if grep -qE 'FATFLOOR_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
        echo "FAIL: seed $SEED: at least one case failed or was inconclusive."
        rc=1
        continue
    fi
    for marker in zero-to-below zero-to-below-big within-fatigued stable-cross-floor stable-above-zero load-floor load-warning; do
        if ! grep -qE "FATFLOOR_PROBE: $marker .* PASS" <<< "$lines"; then
            echo "FAIL: seed $SEED: missing PASS for $marker"
            exit 1
        fi
    done
    if ! grep -qE 'FATFLOOR_PROBE: done failures=0' <<< "$lines"; then
        echo "FAIL: seed $SEED: probe did not finish with failures=0"
        exit 1
    fi
done

[ "$rc" -eq 0 ] || exit 1
echo "PASS: LoseFatigue keeps Strength and the fatigue floor current on every band change, on seeds 1 and 2."
