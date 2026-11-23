#!/bin/bash
# gate: live
# inc-rk030: finishing a meal restores max(1,nutrition/10) fatigue, capped at
# the maximum; a meal started satiated restores none; a vomit costs 1 fatigue.
#
# fact: character and its maximum fatigue -- fixture orc-barbarian-seed1-opt0822, INCURSION_LOAD; the probe reads Attr[A_FAT] itself
# fact: hunger before each meal -- the probe sets it with SetStatiDur
# fact: fatigue before each meal -- the probe sets cFP from the maximum
# fact: nutrition of each food -- lib/mundane.irh and lib/m_items.irh, fixed data read from TITEM
# fact: whether a bite vomits -- !random(20): the probe bites up to 400 apples at 7200 hunger until one vomits, INCONCLUSIVE (red) if none (bead inc-rk030)
# fact: the message -- read from the terminal message history (MsgHistory), emptied before each meal
# fact: the full-stomach prompts -- answered by the probe's own key hook
# fact: settings -- tools/fixtures/options-2026-08-22.dat, INCURSION_OPTIONS
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/eat-fatigue.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-eat_fatigue"
out="$(INCURSION_EAT_FATIGUE_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run_status=$?

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "$out" | tail -20
    echo "FAIL: no $log. The probe never wrote anything."
    exit 1
fi

lines="$(grep 'EATFAT_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no EATFAT_PROBE lines."
    exit 1
fi
echo "$lines"
echo "Specimen: $log"
if [ "$run_status" -ne 0 ]; then
    echo "$out" | tail -20
    echo "FAIL: headless exited $run_status"
    exit 1
fi

if grep -qE 'EATFAT_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
# told=1 is "You feel less tired." in the message history; the probe also
# requires it exactly when fatigue rose.
for marker in restore-ration restore-fresh-food restore-apple cap-near-max; do
    if ! grep -qE "EATFAT_PROBE: $marker .* told=1 PASS" <<< "$lines"; then
        echo "FAIL: missing PASS with the message for $marker"
        exit 1
    fi
done
for marker in cap-at-max satiated-start; do
    if ! grep -qE "EATFAT_PROBE: $marker .* told=0 PASS" <<< "$lines"; then
        echo "FAIL: missing PASS without the message for $marker"
        exit 1
    fi
done
for marker in vomit; do
    if ! grep -qE "EATFAT_PROBE: $marker .* PASS" <<< "$lines"; then
        echo "FAIL: missing PASS for $marker"
        exit 1
    fi
done
if ! grep -qE 'EATFAT_PROBE: done failures=0' <<< "$lines"; then
    echo "FAIL: probe did not finish with failures=0"
    exit 1
fi

echo "PASS: eating restores fatigue as ruled, stops at the cap, skips a satiated start, and a vomit costs one."
