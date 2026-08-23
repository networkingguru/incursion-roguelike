#!/bin/bash
# Does a Wand of Cleansing Light roll the damage its own inventory line prints?
# Finding PA-08-F1 of bd inc-tek.8.8.
#
# THE DEFECT. The wand's page promises "2d6 points of damage per magical plus
# the wand possesses" (lib/m_items.irh). Its damage field asked for
# LEVEL_2PER1 -- twice the CASTING level -- and for an item the casting level
# is the item's own level (src/Magic.cpp:470), which for this wand is three
# times its plus plus one (src/Item.cpp:2210, Level: PLUS_3PER1_ADD1). So the
# plus was multiplied twice and the wand rolled (6*plus+2)d6.
#
# THE ORACLE is the game arguing with itself on one screen, so no second build
# is needed to read it. Two places print the same field:
#
#   the wand's own inventory line, which calls TEffect::Power(GetPlus(), ...)
#   and so passes the PLUS as the level (src/Magic.cpp:135-157, printed at
#   src/Message.cpp:1326-1327) -- "Wand +2 of Cleansing Light [4d6+3]";
#
#   the damage line the game prints when the beam lands, which is the dice the
#   engine actually rolled (src/Effects.cpp:271-297) -- "Aether sponge's
#   Damage: 4d6 = 9 Physical Damage".
#
# Before the fix those two read 4d6 and 14d6 on the same +2 wand in the same
# turn. After it they read the same number, and that number is 2 per plus.
#
# Usage: tools/check_wand_cleansing.sh     (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
PLUS=2          # what tools/keys/wand-cleansing.keys types at "Enter Item Level:"
WANT=$((2 * PLUS))

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/wand-cleansing.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script could not find something on screen. Run: $run"
    exit 2
fi

held="$run/logs/screens/0001-wand-in-hand.txt"
fired="$run/logs/screens/0002-fired.txt"
for f in "$held" "$fired"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: no screen dumped at $f"; exit 2; }
done

# The acquisition list is walked by cursor, not by menu letter, so read the
# item's name back before believing anything else about the run.
name="$(grep -o "Wand +[0-9]* of Cleansing Light \[[0-9]*d[0-9]*[+-]*[0-9]*\]" "$held" | head -1)"
[ -n "$name" ] || {
    echo "INCONCLUSIVE: the character never held a Wand of Cleansing Light of a"
    echo "              known plus, so the session measured nothing. Screen: $held"
    exit 2
}
case "$name" in
    "Wand +$PLUS of "*) ;;
    *) echo "INCONCLUSIVE: expected a +$PLUS wand, screen shows: $name"; exit 2 ;;
esac

printed="$(echo "$name" | sed -e 's/.*\[//' -e 's/d[0-9].*//')"

rolled="$(grep -o "Damage: (\{0,1\}[0-9]*d[0-9]*" "$fired" | head -1 |
          sed -e 's/.*Damage: (\{0,1\}//' -e 's/d[0-9]*//')"
[ -n "$rolled" ] || {
    echo "INCONCLUSIVE: the beam never landed, so nothing rolled. Screen: $fired"
    exit 2
}

echo "  wand's own line: ${printed}d6    rolled at the target: ${rolled}d6"

rc=0
if [ "$printed" != "$rolled" ]; then
    echo "FAIL: the wand rolls ${rolled}d6 while its own inventory line prints ${printed}d6."
    echo "      Screens: $held"
    echo "               $fired"
    rc=1
fi
if [ "$rolled" != "$WANT" ]; then
    echo "FAIL: a +$PLUS wand rolled ${rolled}d6; its page promises 2d6 per plus, so ${WANT}d6."
    echo "      Screen: $fired"
    rc=1
fi
[ "$rc" = 0 ] && echo "  ok: a +$PLUS Wand of Cleansing Light rolls ${WANT}d6, which is what it says it does"
exit $rc
