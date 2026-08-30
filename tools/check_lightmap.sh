#!/bin/bash
# Does the light map (src/Light.cpp) obey its invariants on a real session?
#
# Plays tools/keys/smoke.keys on seed 1 with INCURSION_LIGHT_PROBE=1, so
# every ShowMap appends a block to the run's logs/light.log, then hands the
# log to tools/lightmap_check.py: every lit cell is reached, a light-carrying
# player stands lit, source neighbours are lit, and sole-source light dims.
#
# Usage: tools/check_lightmap.sh              exit 0 pass, 1 fail, 2 inconclusive
#        tools/check_lightmap.sh --selftest   proves the parser's assertions bite
#
# Needs the headless build: BACKEND=posix ./build_macos.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ "${1:-}" = "--selftest" ]; then
    exec python3 tools/lightmap_check.py --selftest
fi

SEED=1
KEYS=tools/keys/smoke.keys
[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
out="$(INCURSION_LIGHT_PROBE=1 tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
if printf '%s\n' "$out" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: $KEYS never entered a map. Run: $run"
    exit 2
fi
log="$run/logs/light.log"
[ -f "$log" ] || {
    echo "INCONCLUSIVE: no light.log in $run -- the probe switch did not take"
    exit 2
}
python3 tools/lightmap_check.py "$log"
status=$?
[ "$status" -eq 0 ] || echo "log: $log"
exit $status
