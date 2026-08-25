#!/bin/bash
# Regression check for the Rod of Lordly Might's paralyzing-touch count,
# inc-tek.8.8. Its page promises three touches; the script used to grant seven.
#
# The ROLM_PROBE build records the actual TOUCH_ATTACK stati at Fight.cpp's
# landed-touch path, before and after its decrement. A frozen mummy survives
# while repeated eastward attacks consume the effect. The oracle therefore
# reads engine state, not lib/m_items.irh: exactly three "before" records with
# magnitudes 3, 2, 1, followed by removal.
#
# Build: EXTRA_CXXFLAGS=-DROLM_PROBE OUT=incursion-rolm BACKEND=posix ./build_macos.sh
# Usage: tools/check_rod_lordly_might.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN=./incursion-rolm
KEYS=tools/keys/rod-lordly-might.keys
SEED=1

[ -x "$BIN" ] || {
    echo "FAIL: $BIN not built. Run:"
    echo "  EXTRA_CXXFLAGS=-DROLM_PROBE OUT=incursion-rolm BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(INCURSION_BIN="$BIN" INCURSION_OPTIONS=tools/gates/Options.Dat \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"

if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi
if echo "$OUT" | grep -q "the key script looked for something"; then
    echo "FAIL: the key script did not find an expected screen"
    echo "$OUT"
    exit 1
fi

LOG="$RUN/logs/rolm-touch.log"
[ -f "$LOG" ] || {
    echo "FAIL: no probe log at $LOG"
    exit 1
}

BEFORE="$(awk '/^before effect=paralysis / {print $3}' "$LOG" | sed 's/magnitude=//' | paste -sd, -)"
AFTER="$(awk '/^after effect=paralysis / {print $3 "/" $4}' "$LOG" | sed 's/magnitude=//; s/present=//' | paste -sd, -)"
COUNT="$(awk '/^before effect=paralysis / {n++} END {print n+0}' "$LOG")"

echo "Rod paralyzing touches: $COUNT"
echo "  before magnitudes: $BEFORE"
echo "  after magnitude/present: $AFTER"

if [ "$COUNT" != 3 ] || [ "$BEFORE" != "3,2,1" ] || [ "$AFTER" != "2/1,1/1,0/0" ]; then
    echo "FAIL: expected exactly three landed touches, counting 3 -> 2 -> 1 -> removed"
    exit 1
fi

echo "PASS: the Rod of Lordly Might's paralyzing effect ended after three landed touches"
