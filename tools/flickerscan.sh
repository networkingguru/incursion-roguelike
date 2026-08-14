#!/bin/bash
# Sample the screen's brightness while the game runs, then line every sample up
# against the game's own repaints.
#
# The in-game FLICKER_PROBE cannot answer this question. It runs inside
# libtcod's actual_rendering(), so it samples only when the game presents a
# frame -- and a brightness change that happens BETWEEN presents is invisible
# to it. So sample the composited screen on our own clock instead.
#
# This version starts itself when the game appears and stops itself when the
# game exits. You cannot mistime the window, and it cannot keep measuring your
# desktop after you quit.
#
# HOW TO USE IT
#   1. Run this first. It waits for the game.
#   2. Start ./incursion-palettelog in another terminal.
#   3. Reproduce the flash: tap a key, let it dim, tap again. Repeat.
#   4. Quit the game. The scan stops itself and writes the report.
#
# Needs Screen Recording permission for THIS terminal, or macOS silently
# returns black frames: System Settings > Privacy & Security > Screen &
# System Audio Recording. flickerscan.py aborts if it sees black.
#
# Usage: tools/flickerscan.sh [max_seconds]      (default 120)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="${BIN:-incursion-palettelog}"
MAX="${1:-120}"
INTERVAL=0.5
LOG="$ROOT/logs/flickerscan.log"
PALETTE="$ROOT/logs/palette.log"
SHOTS="$(mktemp -d)"
trap 'rm -rf "$SHOTS"' EXIT

command -v python3 >/dev/null || { echo "needs python3"; exit 1; }
python3 -c "import PIL" 2>/dev/null || { echo "needs Pillow: python3 -m pip install --user Pillow"; exit 1; }

echo "Waiting for $BIN. Start it now in another terminal."
while ! pgrep -x "$BIN" >/dev/null; do
    sleep 0.5
done

LIMIT=$(python3 -c "print(int($MAX / $INTERVAL))")
echo "Game is up. Sampling every ${INTERVAL}s until you quit it (max ${MAX}s)."
echo
echo "  >>> Reproduce it now: tap a key, let it dim, tap again. <<<"
echo

i=0
while pgrep -x "$BIN" >/dev/null && [ "$i" -lt "$LIMIT" ]; do
    i=$((i + 1))
    screencapture -x -m "$SHOTS/$(printf '%05d' "$i").png" 2>/dev/null
    sleep "$INTERVAL"
done

echo
echo "Game exited. Took $i captures. Measuring..."
echo

# The palette log gives each sample a "how long since the game last repainted"
# figure, which is the question this whole scan exists to answer.
if [ -f "$PALETTE" ]; then
    python3 tools/flickerscan.py "$SHOTS/*.png" "$PALETTE" 2>&1 | tee "$LOG"
else
    echo "No $PALETTE -- run ./incursion-palettelog, not ./incursion." | tee "$LOG"
    python3 tools/flickerscan.py "$SHOTS/*.png" 2>&1 | tee -a "$LOG"
fi

echo
echo "Report saved to logs/flickerscan.log"
