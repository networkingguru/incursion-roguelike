#!/bin/bash
# Does the Ring of Elemental Command (Water) command water creatures, or fire?
# Finding PA-08-F3 of bd inc-tek.8.8.
#
# THE DEFECT. Two adjacent lines disagreed. The ring READ how well its wearer
# already commands water and then WROTE the grant against fire:
#
#   clev = EVictim->GetStatiMag(COMMAND_ABILITY,MA_WATER);
#   EVictim->GainPermStati(COMMAND_ABILITY,EItem,SS_ITEM, MA_FIRE, ...
#
# so the wearer's water command was measured, thrown away, and command of fire
# creatures handed over instead. The ring's own page promises water. The three
# sibling rings each read and write their own element.
#
# THE ORACLE is the character sheet's Special Abilities block, which prints one
# line per commandable type (src/Sheet.cpp:492-499) and gets the words from
# MTypeNames (src/Tables.cpp:983,988). The wearer reads "Command Fire
# Creatures" before the fix and "Command Water Creatures" after it. The column
# is narrow and clips the line, so the check matches the part that fits, which
# still tells the two elements apart.
#
# Usage: tools/check_ring_water_command.sh     (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/ring-water-command.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script could not find something on screen. Run: $run"
    exit 2
fi

worn="$run/logs/screens/0001-ring-on.txt"
sheet="$run/logs/screens/0002-specials.txt"
for f in "$worn" "$sheet"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: no screen dumped at $f"; exit 2; }
done

# The acquisition list is walked by cursor, not by menu letter, so read the
# ring's own name back before believing anything the sheet says.
grep -q "Left Ring    :Ring of Elemental Command (Water)" "$worn" || {
    echo "INCONCLUSIVE: the Ring of Elemental Command (Water) never reached a"
    echo "              finger, so the session measured nothing. Screen: $worn"
    exit 2
}

grep -q "Special Abilities" "$sheet" || {
    echo "INCONCLUSIVE: the sheet never scrolled to Special Abilities. Screen: $sheet"
    exit 2
}

rc=0
if grep -q "Command Fire Creat" "$sheet"; then
    echo "FAIL: the water ring grants command of FIRE creatures."
    echo "      Screen: $sheet"
    rc=1
fi
if ! grep -q "Command Water Crea" "$sheet"; then
    echo "FAIL: the water ring grants no command of water creatures at all."
    echo "      Screen: $sheet"
    rc=1
fi
[ "$rc" = 0 ] && echo "  ok: the water ring commands water creatures and no fire ones"
exit $rc
