#!/bin/bash
# Regression check for the sacrifice-list wildcard bug, inc-upw.27.
#
# A god's SACRIFICE_LIST is a list of (category, value) pairs.
# Character::Sacrifice walked it two slots at a time and stopped at the first
# zero in the LEFT slot. MA_ALL is 0, so a MA_ALL row terminated the list
# instead of matching every creature, and every row after it was unreachable.
#
# Khasrach, the orc god, is the severe case: seven rows, of which the last
# five are MA_ALL. Only MA_ORC (abomination) and MA_GOBLINOID (angry) were
# ever read, so his altar refused every ordinary corpse and his two live rows
# were both punishments.
#
# Three runs, because one is not enough:
#
#   sacrifice-wildcard.keys   a dwarf corpse -- matches ONLY through MA_ALL.
#                             Must be accepted. This is the bug.
#   sacrifice-goblinoid.keys  a kobold corpse -- matches row 1, which is
#                             BEFORE the first MA_ALL and was always read.
#                             Must still anger him, exactly as before.
#   sacrifice-aiswin.keys     a dwarf corpse at an AISWIN altar. Aiswin's own
#                             script forces the category to MA_CHOICE1, whose
#                             row sits BELOW his MA_ALL rows. This is the only
#                             run that proves the rows below MA_ALL are read.
#                             It is the case Brian hit in play, inc-52b.
#
# Without the second run this check cannot tell "MA_ALL matches now" from
# "the loop matches anything now". Without the third it cannot see a loop
# that stops one row too early, because Khasrach has nothing below his
# MA_ALL rows to lose.
#
# Measured 2026-08-18, seed 1, same key script, one line of src/Prayer.cpp
# different between the two builds:
#
#   dwarf corpse   before: "Khasrach seems uninterested in your offering."
#                  after:  "Khasrach is impressed", sacVal 88, favour 0 -> 88
#   kobold corpse  before: "Anger: Khasrach +1 (offensive sacrifice)."
#                  after:  identical
#
# Usage: tools/check_sacrifice.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

# Run one key script and leave its screen directory in $SCREENS. Every failure
# here is INCONCLUSIVE, not FAIL: a session that did not reach the altar has
# measured nothing, and reporting nothing as a regression sends somebody
# hunting a bug that is not there. That mistake is inc-loa.3.
run_script() {
    local keys="$1" corpse="$2" god="$3" out run
    out="$(tools/headless.sh "$keys" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    SCREENS="$run/logs/screens"

    if echo "$out" | grep -q "NO GAMEPLAY"; then
        echo "INCONCLUSIVE: $keys never entered a map, so it measured nothing"
        return 1
    fi
    if [ ! -d "$SCREENS" ]; then
        echo "INCONCLUSIVE: $keys left no screen dumps at $SCREENS"
        return 1
    fi
    if ! grep -qh "Created an altar to $god" "$SCREENS"/*.txt; then
        echo "INCONCLUSIVE: $keys did not create the $god altar."
        echo "  Wizard option [M] Create Altar has moved, or the character is"
        echo "  not in wizard mode. Fix the key script. Screens: $SCREENS"
        return 1
    fi
    if ! grep -qh "\[w\] $corpse corpse" "$SCREENS"/*.txt; then
        echo "INCONCLUSIVE: $keys did not offer a $corpse corpse as [w]."
        echo "  The 'Offer what?' menu letters have moved, or the walk no"
        echo "  longer ends on that corpse. Fix the key script."
        echo "  Screens: $SCREENS"
        return 1
    fi
    return 0
}

# 1. The bug itself. A dwarf is neither orc nor goblinoid, so it can only be
#    caught by a MA_ALL row.
run_script tools/keys/sacrifice-wildcard.keys dwarf Khasrach || exit 1
WILD="$SCREENS"

if grep -qh "seems uninterested" "$WILD"/*.txt; then
    echo "FAIL: Khasrach refused a dwarf corpse."
    echo "  His five MA_ALL rows (lib/religion.irh:2830-2834) are unreachable"
    echo "  again, so the loop in src/Prayer.cpp is stopping at the left slot"
    echo "  of a pair instead of at a whole zero row. See inc-upw.27."
    echo "  Screens: $WILD"
    exit 1
fi
if ! grep -qh "is impressed" "$WILD"/*.txt; then
    echo "FAIL: Khasrach neither refused nor was impressed by a dwarf corpse."
    echo "  Something else in the sacrifice path has changed. Screens: $WILD"
    exit 1
fi

# 2. The control. Row 1 was always read; the fix must not have touched it.
run_script tools/keys/sacrifice-goblinoid.keys kobold Khasrach || exit 1
GOB="$SCREENS"

if ! grep -qh "offensive sacrifice" "$GOB"/*.txt; then
    echo "FAIL: a kobold corpse no longer angers Khasrach."
    echo "  Row 1 of his list is MA_GOBLINOID SAC_ANGRY and sits before the"
    echo "  first MA_ALL, so it was reachable even with the old loop. The fix"
    echo "  has changed behaviour it had no business changing. See inc-upw.27."
    echo "  Screens: $GOB"
    exit 1
fi

# 3. The rows BELOW the MA_ALL rows. Aiswin's PRE(EV_SACRIFICE) handler sets
#    e.EParam = MA_CHOICE1 for any corpse that is not a blood-vengeance kill
#    (lib/religion.irh:299-315). That makes sacType 125, which switches off
#    the isMType branch entirely, so the ONLY row that can match is row 6,
#    MA_CHOICE1 SAC_UNWORTHY -- and it sits below both MA_ALL rows. With the
#    old loop it was unreachable and the player got the wrong message. This
#    is inc-52b, the bug Brian reported from play.
run_script tools/keys/sacrifice-aiswin.keys dwarf Aiswin || exit 1
AIS="$SCREENS"

if grep -qh "seems uninterested" "$AIS"/*.txt; then
    echo "FAIL: Aiswin said he was uninterested in a dwarf corpse."
    echo "  His MA_CHOICE1 row (lib/religion.irh:140) is unreachable again, so"
    echo "  the loop in src/Prayer.cpp is stopping at the left slot of a pair"
    echo "  instead of at a whole zero row. See inc-52b and inc-upw.27."
    echo "  Screens: $AIS"
    exit 1
fi
if ! grep -qh "Insufficient" "$AIS"/*.txt; then
    echo "FAIL: Aiswin neither refused the corpse nor called it insufficient."
    echo "  Expected MSG_INSUFFICIENT, from the SAC_UNWORTHY arm of"
    echo "  Character::Sacrifice. Either his classification handler no longer"
    echo "  sets MA_CHOICE1, or the dwarf corpse now carries a CORPSE_FLAG and"
    echo "  counts as blood vengeance. Screens: $AIS"
    exit 1
fi

echo "PASS: MA_ALL matches a dwarf corpse, MA_GOBLINOID still angers, and"
echo "      Aiswin's MA_CHOICE1 row below the MA_ALL rows is reachable"
exit 0
