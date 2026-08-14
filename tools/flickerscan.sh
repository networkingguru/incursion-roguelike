#!/bin/bash
# Sample the screen's brightness on a fixed clock while you reproduce the flash.
#
# The in-game FLICKER_PROBE cannot answer this question. It runs inside
# libtcod's actual_rendering(), so it samples only when the game presents a
# frame -- and the game presents about twice a second, with gaps measured up to
# 3.4 seconds. A brightness change that happens BETWEEN presents is invisible
# to it. That fits both the flat 8.99 reading it gave and the multi-second ramp
# this flicker is reported to have.
#
# So sample the composited screen on our own clock instead.
#
# HOW TO USE IT
#   1. Start the game and get to the options screen first.
#   2. In another terminal, run this.
#   3. When it says GO, move up and down between options until it stops.
#   4. Read the verdict.
#
# Usage: tools/flickerscan.sh [seconds]      (default 30)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SECS="${1:-30}"
INTERVAL=0.5
SHOTS="$(mktemp -d)"
trap 'rm -rf "$SHOTS"' EXIT

command -v python3 >/dev/null || { echo "needs python3"; exit 1; }
python3 -c "import PIL" 2>/dev/null || { echo "needs Pillow: python3 -m pip install --user Pillow"; exit 1; }

COUNT=$(python3 -c "print(int($SECS / $INTERVAL))")

echo "Sampling the main display every ${INTERVAL}s for ${SECS}s (${COUNT} captures)."
echo "Captures go to a temp dir and are deleted afterwards."
echo
echo "  >>> GO -- move up and down between options now <<<"
echo

for i in $(seq -f "%04g" 1 "$COUNT"); do
    screencapture -x -m "$SHOTS/shot$i.png" 2>/dev/null
    sleep "$INTERVAL"
done

echo
echo "Done capturing. Measuring..."
echo
python3 tools/flickerscan.py "$SHOTS/*.png"
