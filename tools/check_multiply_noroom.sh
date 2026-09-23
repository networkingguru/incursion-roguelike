#!/bin/bash
# gate: live
# inc-dpni: a copy Multiply could not place must not be placed again.
#
# ORACLE. Creature::Multiply places a copy on the parent's own square; PlaceAt
# kicks it to (1,1) and calls PlaceNear, and when PlaceNear finds no free square
# it deletes the copy (m=NULL, x=y=-1, F_DELETE). Multiply then set m again and
# re-placed the dead copy, tripping InBounds() in Map::At (inc/Map.h:275). The
# switch INCURSION_MULTIPLY_NOROOM makes PlaceNear refuse the copy Multiply is
# placing, so the state is reached on demand and the switch line is countable.
#
# Pinned seeds 24 and 25, tools/gates/Options.Dat, tools/keys/dive.keys: each
# produced two refused copies. Raise the build first:
#   BACKEND=posix ./build_macos.sh
#
# Exit: 0 PASS (guard held, no Map.h:275 assert); 1 FAIL (the assert fired);
#       2 UNMEASURED (the switch reached no copy, so nothing was measured).
# Usage: tools/check_multiply_noroom.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

SEEDS="24 25"
RUNDIR="$ROOT/logs/multiply-noroom"
mkdir -p "$RUNDIR"
HITS=0
ASSERTS=0

for s in $SEEDS; do
    RUN="$RUNDIR/seed$s"
    rm -rf "$RUN"
    INCURSION_OPTIONS=tools/gates/Options.Dat \
    INCURSION_MULTIPLY_NOROOM=1 \
    INCURSION_RUN_DIR="$RUN" \
        tools/headless.sh tools/keys/dive.keys "$s" > "$RUN.out" 2>&1
    h="$(grep -c 'INCURSION_MULTIPLY_NOROOM: refused a copy' \
        "$RUN/logs/errors.log" 2>/dev/null || true)"
    a="$(grep -c 'inc/Map.h, line 275' "$RUN/logs/errors.log" 2>/dev/null || true)"
    [ -n "$h" ] || h=0
    [ -n "$a" ] || a=0
    HITS=$((HITS + h))
    ASSERTS=$((ASSERTS + a))
    echo "seed $s: refused copies $h, Map.h:275 asserts $a (run $RUN)"
done

if [ "$ASSERTS" -gt 0 ]; then
    echo "FAIL: $ASSERTS Map.h:275 assert(s) -- Multiply re-placed a deleted copy."
    exit 1
fi
if [ "$HITS" -eq 0 ]; then
    echo "INCONCLUSIVE: the switch refused no copy on seeds $SEEDS; the path was"
    echo "              not reached, so nothing about the guard was measured."
    exit 2
fi
echo "PASS: $HITS refused copies, no Map.h:275 assert."
exit 0
