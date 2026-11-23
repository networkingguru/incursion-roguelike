#!/bin/bash
# gate: live
# inc-jw0hw: the SDL build records frames on a virtual clock (INCURSION_FRAMES).
# Runs the darkvision scene windowless; passes when the frame count is within
# 0.9x..1.1x of (total of the key script's @pause values) / 33 ms, and the
# script's @shot file exists and is not empty.
# Needs the SDL build (./incursion). The main session runs it; it launches SDL.
# fact: pause total -- read from the key script at run time
# fact: character -- fixture kobold-rogue-seed1
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS
# Exit 0 on PASS, 1 on FAIL, 2 on INCONCLUSIVE.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
SRC_KEYS=tools/keys/inc-moh9-darkvision-scene.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=kobold-rogue-seed1

[ -x ./incursion ] || {
    echo "INCONCLUSIVE: ./incursion (the SDL build) is missing. Run: ./build_macos.sh"
    exit 2
}

# Build the fixture with the headless binary; the SDL binary cannot do it.
LOAD="$(tools/fixture_cache.sh "$FIXTURE")" || {
    echo "INCONCLUSIVE: tools/fixture_cache.sh could not build $FIXTURE."
    exit 2
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-frame-recorder"
mkdir -p "$RUN_DIR"
KEYS="$RUN_DIR/scene.keys"
SHOT="$RUN_DIR/shot.bmp"
FRAMES="$RUN_DIR/frames"
sed "s#SHOTFILE_PLACEHOLDER#shot.bmp#" "$SRC_KEYS" > "$KEYS"

total="$(grep -E '^@pause[[:space:]]+[0-9]+' "$KEYS" | awk '{ s += $2 } END { print s + 0 }')"
if [ "$total" -le 0 ]; then
    echo "INCONCLUSIVE: no @pause lines in $SRC_KEYS."
    exit 2
fi

INCURSION_BIN=./incursion INCURSIONFONTPATH="$ROOT/fonts" \
    INCURSION_FRAMES="$FRAMES" INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN_DIR/run.out" 2>&1

count="$(find "$FRAMES" -name 'f*.bmp' 2>/dev/null | wc -l | tr -d ' ')"
want=$(( total / 33 ))
lo=$(( want * 9 / 10 ))
hi=$(( want * 11 / 10 ))
echo "pause total ${total} ms; frames ${count}; expected ${want} (${lo}..${hi})"
echo "Specimen: $RUN_DIR"

if [ "$count" -lt "$lo" ] || [ "$count" -gt "$hi" ]; then
    echo "FAIL: frame count ${count} is outside ${lo}..${hi}."
    tail -n 5 "$RUN_DIR/run.out"
    exit 1
fi
if [ ! -s "$SHOT" ]; then
    echo "FAIL: $SHOT is missing or empty."
    tail -n 5 "$RUN_DIR/run.out"
    exit 1
fi
echo "PASS: ${count} frames for ${total} ms of pauses, and the shot was written."
exit 0
