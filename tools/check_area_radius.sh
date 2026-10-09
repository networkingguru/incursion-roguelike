#!/bin/bash
# gate: live
# inc-lmw4: a globe's and a field's first pulse reach lval squares, as the lasting Field does.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/area-radius.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-area-radius"
out="$(INCURSION_AREA_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. The probe never wrote anything -- is"
    echo "      AreaRadiusProbe still called from Game::Play()?"
    exit 1
fi

lines="$(grep 'AREA_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no AREA_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"

if grep -qE 'AREA_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
for marker in 'globe dist=5 affected=1' 'globe dist=6 affected=1' 'globe dist=7 affected=0' \
    'field dist=3 pulse=1 lasting=1' 'field dist=4 pulse=1 lasting=1' \
    'field dist=5 pulse=0 lasting=0' 'PASS'; do
    if ! grep -qE "AREA_PROBE: $marker$" <<< "$lines"; then
        echo "FAIL: missing result $marker"
        exit 1
    fi
done

echo "PASS: globe and field first pulse reach lval squares, matching the lasting Field."
