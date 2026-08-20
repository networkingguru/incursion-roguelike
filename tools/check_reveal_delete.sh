#!/bin/bash
# Regression check for inc-upw.37: a creature deleted by its own Reveal(), and
# the caller that keeps using its map pointer.
#
# WHAT THE DEFECT IS. Creature::MakeNoise checks that the caster is still
# standing on the map (src/Creature.cpp:342), then calls Reveal(true), then
# dereferences c->m. Reveal can delete the creature between those two lines:
# it removes the HIDING stati, removing it runs StatiOff -> CalcValues,
# CalcValues recomputes the size, a size of SZ_HUGE or above needs a 3x3
# footprint, so CalcValues calls PlaceNear -- and PlaceNear deletes any
# non-player thing it cannot seat, setting m = NULL and x = y = -1. The guard
# is correct; it just runs before the call that invalidates it. Three sibling
# callers had the same hole and were fixed with it (src/Fight.cpp's A_ROAR
# case, src/Move.cpp's TerrainEffects fall path).
#
# WHY SEED 3390. The defect needs a hiding SZ_HUGE monster standing where a
# 3x3 will not fit, which is rare. Seed 3390 parks exactly such a monster in
# exactly such a square -- but only under the inc-65j repair to
# Rect::PlaceWithin, which changes where rooms are. That repair SHIPPED on
# 2026-08-20, so a stock build reaches the branch and this check needs no
# special binary. Before it shipped the same run needed
# -DINCURSION_OOB_PWFIX_WIDEN; docs/evidence/inc-upw.37/ was recorded that way
# and its numbers still stand, because the flag and the shipped code are the
# same change.
#
# The coupling is worth stating plainly: if inc-65j is ever reverted or the
# rectangle repair changes shape, this check may stop reaching the branch and
# will go green for the wrong reason. It would then be INCONCLUSIVE dressed as
# a pass, and the fix it guards would be unguarded.
#
# WHAT IT ASSERTS. On seed 3390 the session must exit 0 and must have entered a
# map. Before the fix it exits 139, faulting at KERN_INVALID_ADDRESS 0x10 in
# Map::At(this=0x0, x=-1, y=-1), after two screens.
#
# THE SETTINGS ARE PINNED, and that is not decoration. The same binary and seed
# under tools/gates/Options.Dat plays a different game in which the character
# dies early and never reaches the branch -- a clean-looking run that says
# nothing. docs/evidence/inc-upw.37/Options.Dat is a snapshot of the settings
# the crash was recorded under, kept beside the evidence so that Brian playing
# the game and rewriting Options.Dat cannot quietly turn this check green.
#
# Ends: 0 pass, 1 fail (the crash is back), 2 the check could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=3390
KEYS="tools/keys/dive.keys"
OPTS="$ROOT/docs/evidence/inc-upw.37/Options.Dat"
BIN="incursion-headless"

[ -f "$OPTS" ] || {
    echo "INCONCLUSIVE: the pinned settings file is missing: $OPTS"
    echo "Without it this check measures whatever Brian last played with."
    exit 2
}

[ -x "./$BIN" ] || {
    echo "INCONCLUSIVE: ./$BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

OUT_LOG="$(mktemp)"
INCURSION_OPTIONS="$OPTS" INCURSION_BIN="./$BIN" \
    tools/headless.sh "$KEYS" "$SEED" > "$OUT_LOG" 2>&1
STATUS=$?

# headless.sh promotes a run that never entered a map to exit 5, so a session
# that measured nothing cannot be read here as a pass.
case $STATUS in
    0) ;;
    139)
        echo "FAIL: seed $SEED segfaulted (exit 139). inc-upw.37 is back."
        echo
        sed -n '/--- after the session ---/,$p' "$OUT_LOG"
        echo
        echo "Expect the fault at KERN_INVALID_ADDRESS 0x10 in Map::At, reached"
        echo "from Creature::MakeNoise. To see it, re-run under lldb with the"
        echo "command files in docs/evidence/inc-upw.37/:"
        echo "  INCURSION_OPTIONS=$OPTS INCURSION_BIN=./$BIN \\"
        echo "    INCURSION_LAUNCHER=\"lldb -b -s docs/evidence/inc-upw.37/watch.lldb --\" \\"
        echo "    tools/headless.sh $KEYS $SEED -headless"
        rm -f "$OUT_LOG"
        exit 1 ;;
    5)
        echo "INCONCLUSIVE: the run never entered a map, so it measured nothing."
        sed -n '/--- after the session ---/,$p' "$OUT_LOG"
        rm -f "$OUT_LOG"
        exit 2 ;;
    *)
        echo "FAIL: seed $SEED ended unexpectedly (exit $STATUS)."
        sed -n '/--- after the session ---/,$p' "$OUT_LOG"
        rm -f "$OUT_LOG"
        exit 1 ;;
esac

SCREENS="$(grep -m1 '^screens:' "$OUT_LOG" | awk '{print $2}')"
rm -f "$OUT_LOG"

echo
echo "PASS: seed $SEED plays to the end ($SCREENS screens) instead of"
echo "      segfaulting. A hiding monster that its own Reveal() deletes no"
echo "      longer takes the caster's map pointer down with it."
exit 0
