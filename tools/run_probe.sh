#!/bin/bash
# Temporary diagnostic launcher. Runs the game with the save/load and map
# probes enabled, so the environment variables cannot be forgotten.
#
# Writes logs/saveprobe.log and logs/mapprobe.log.
# Delete this script once the saved-game position bug is fixed.
cd "$(dirname "$0")/.." || exit 1

export INCURSION_SAVE_PROBE=1
export INCURSION_MAP_PROBE=1

echo "probes on -> logs/saveprobe.log, logs/mapprobe.log"
./incursion "$@"

echo
echo "--- saveprobe.log ---"
cat logs/saveprobe.log 2>/dev/null || echo "(nothing written)"
