#!/bin/bash
# Does the Ring of Elemental Command (Fire) amplify cold alone, or everything?
# Finding PA-08-F2 of bd inc-tek.8.8.
#
# THE DEFECT. The ring's page curses its wearer with "150~ damage from all
# cold-based attacks (before resistance)" (lib/m_items.irh). Its handler asked
# "if (e.DType = AD_COLD)" -- a single equals sign. That is an assignment, not
# a comparison, and the expression yields what it assigned, which is 2 and
# never zero. So the ring wrote cold into every wound its wearer took, tested
# what it had just written, and multiplied the lot by 3/2.
#
# THE ORACLE is the damage line the game prints at the victim, which names both
# the amount and the TYPE (src/Effects.cpp:271-297). The wearer shoots himself
# with a wand, so no monster is involved and nothing else can write over the
# window.
#
#   The measurement. A Wand of Shards deals AD_SLASH, a type the ring has no
#   business touching. Before the fix that shot read "4d10 = 28 Cold"; after
#   it, "4d10 = 19 Slashing" -- the type is the wand's own again, and 28 is
#   exactly (19 * 3) / 2, so the multiplier is gone with it.
#
#   The control. A Wand of Ice deals AD_COLD, the one type the curse IS meant
#   to amplify. That shot reads "2d8 = 15 Cold" on both builds. It is what
#   stops the fix from being "delete the block": a deleted curse would drop
#   this number to 10 while leaving the Shards half green. It does NOT prove
#   the 3/2 on its own -- 15 is inside 2d8's range -- it proves the cold path
#   was not disturbed.
#
# Usage: tools/check_ring_fire_curse.sh     (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# Run one key script and echo the first damage line any of its dumps shows.
# The first shot can be refused by the Use Magic check, which is why each
# script fires twice and this takes the first line that appears.
shot() { # <keyscript-basename> -> echoes "<dice> <amount> <type>"
    local out run held line
    out="$(tools/headless.sh "tools/keys/$1.keys" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q "the key script looked for something"; then
        echo "INCONCLUSIVE: $1 could not find something on screen. Run: $run" >&2
        exit 2
    fi

    # The acquisition lists are walked by cursor, not by menu letter, so read
    # the ring back off the inventory screen before believing the shot.
    held="$run/logs/screens/0001-wand-in-hand.txt"
    [ -f "$held" ] || { echo "INCONCLUSIVE: no inventory screen in $run" >&2; exit 2; }
    grep -q "Left Ring    :Ring of Elemental Command (Fire)" "$held" || {
        echo "INCONCLUSIVE: $1 never got the fire ring onto a finger, so the" >&2
        echo "              session measured nothing. Screen: $held" >&2
        exit 2
    }

    line="$(grep -h -o "Damage: [0-9]*d[0-9]* = [0-9]* [A-Za-z]*" \
            "$run"/logs/screens/*.txt | head -1)"
    [ -n "$line" ] || {
        echo "INCONCLUSIVE: $1 never landed a shot on its own caster. Run: $run" >&2
        exit 2
    }
    echo "${line#Damage: }" | tr -d '='
}

rc=0

read -r sdice samt stype <<<"$(shot ring-fire-shards)"
echo "  slashing wand at the wearer: ${sdice} = ${samt} ${stype}"
if [ "$stype" != "Slashing" ]; then
    echo "FAIL: a wand of glass shards dealt ${stype} damage. The ring retypes"
    echo "      every wound its wearer takes, instead of only cold ones."
    rc=1
fi
if [ "$samt" != "19" ]; then
    echo "FAIL: the slashing shot dealt ${samt} on seed $SEED, not the 19 it rolls"
    echo "      unamplified. Before the fix it dealt 28, which is (19 * 3) / 2."
    rc=1
fi

read -r idice iamt itype <<<"$(shot ring-fire-ice)"
echo "  cold wand at the wearer:     ${idice} = ${iamt} ${itype}"
if [ "$itype" != "Cold" ]; then
    echo "FAIL: a wand of ice dealt ${itype} damage, which is not a cold wand's type."
    rc=1
fi
if [ "$iamt" != "15" ]; then
    echo "FAIL: the cold shot dealt ${iamt} on seed $SEED, not the 15 it dealt before"
    echo "      and after this fix. The curse the ring's page promises has moved."
    rc=1
fi

[ "$rc" = 0 ] && echo "  ok: the ring amplifies cold and leaves every other type alone"
exit $rc
