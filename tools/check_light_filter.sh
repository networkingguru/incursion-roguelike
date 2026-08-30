#!/bin/bash
# Does light actually lose strength and colour crossing an ice wall?
#
# tools/check_lightmap.sh proves the light map's invariants but cannot see
# this: its map has no ice, and its invariants are all about what a source
# reaches, not about what a crossed cell takes away. So this check plays two
# sessions that differ by ONE terrain letter and compares the same cell.
#
#   tools/keys/light-ice-off.keys   wall torch, clear cell, floor beyond
#   tools/keys/light-ice-on.keys    wall torch, ICE WALL,   floor beyond
#
# Both place the trio on seed 1, where the player arrives at (111,110): the
# torch at (112,110), the changed cell at (113,110) and the measured floor at
# (114,110), two steps from the torch. The measured cell must be dimmer in the
# ice run, and only the ice run may mark (113,110) in the FILTER grid.
#
# Usage: tools/check_light_filter.sh   exit 0 pass, 1 fail, 2 inconclusive
#
# Needs the headless build: BACKEND=posix ./build_macos.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ICE_X=113; MEASURE_X=114; ROW=110

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# Play one key script and echo "<light digit> <filter char> <run dir>".
play() {
    local keys="$1" out run log
    out="$(INCURSION_LIGHT_PROBE=1 tools/headless.sh "$keys" 1 2>&1)"
    run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
    if printf '%s\n' "$out" | grep -q "NO GAMEPLAY"; then
        echo "INCONCLUSIVE: $keys never entered a map. Run: $run" >&2
        return 2
    fi
    log="$run/logs/light.log"
    [ -f "$log" ] || {
        echo "INCONCLUSIVE: no light.log in $run -- the probe switch did not take" >&2
        return 2
    }
    python3 - "$log" "$ROW" "$ICE_X" "$MEASURE_X" "$run" <<'PY'
import sys
log, row, ice_x, measure_x, run = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
block = open(log).read().split("LIGHT ")[-1].split("\n")
h = int(block[0].split("map=")[1].split()[1])
i = 1
while block[i].startswith("S "):
    i += 1
grid = block[i:i + h]
if block[i + h] != "FILTER":
    sys.stderr.write("INCONCLUSIVE: %s has no FILTER grid\n" % log)
    sys.exit(2)
filt = block[i + h + 1:i + h + 1 + h]
print("%s %s %s" % (grid[row][measure_x], filt[row][ice_x], run))
PY
}

clear_read="$(play tools/keys/light-ice-off.keys)" || exit 2
ice_read="$(play tools/keys/light-ice-on.keys)"    || exit 2
set -- $clear_read; clear_lit="$1"; clear_mark="$2"; clear_run="$3"
set -- $ice_read;   ice_lit="$1";   ice_mark="$2";   ice_run="$3"

fail=0
if [ "$clear_mark" != "-" ]; then
    echo "FAIL: the control run marks ($ICE_X,$ROW) as '$clear_mark'; it placed floor there"
    fail=1
fi
if [ "$ice_mark" != "i" ]; then
    echo "FAIL: the ice run marks ($ICE_X,$ROW) as '$ice_mark', not 'i' -- the ice wall was never placed"
    fail=1
fi
case "$clear_lit" in
    [1-9]) ;;
    *) echo "FAIL: the control run leaves ($MEASURE_X,$ROW) at '$clear_lit'; it must be lit for the comparison to mean anything"
       fail=1 ;;
esac
if [ "$fail" -eq 0 ] && ! [ "$ice_lit" \< "$clear_lit" ]; then
    echo "FAIL: ($MEASURE_X,$ROW) reads '$ice_lit' behind ice and '$clear_lit' in the clear."
    echo "      Light crosses the ice wall undimmed."
    fail=1
fi
if [ "$fail" -ne 0 ]; then
    echo "clear run: $clear_run"
    echo "ice run:   $ice_run"
    exit 1
fi
echo "light filter: ($MEASURE_X,$ROW) reads '$clear_lit' in the clear and '$ice_lit' through one ice wall"
exit 0
