#!/bin/bash
# Regression check: does a flame tongue sword set a corporeal undead alight?
#
# THE PROMISE. The sword's own page in lib/m_items.irh (the "flame tongue"
# entity) tells the player: "When it strikes a corporeal undead, that
# creature's dry, withered flesh catches flame and continues to burn, causing
# it to suffer 3d6 fire damage the first turn after the hit, 2d6 the second
# turn and 1d6 on the third."
#
# THE DEFECT (PA-08-F11, bd inc-tek.8.8). The handler that was supposed to do
# that was an empty stub -- a comment and `return NOTHING;` -- so the sentence
# above was a lie in every game ever played. Nothing burned, and no message
# was ever printed.
#
# THE MEASUREMENT. One session, five readings of one mummy's hit points: the
# first taken as soon as the blow lands, then one per game turn for four more
# turns. See tools/keys/flame-tongue-undead.keys for why a mummy, why the
# monsters are frozen and why each wait is exactly 21 Searches.
#
#   ON A BUILD WITHOUT THE FIX  all five readings are the same number.
#   ON A BUILD WITH IT          two or three drops, then the reading holds.
#
# WHY "TWO OR THREE" AND NOT THREE. The first reading is taken as soon as the
# game hands the keyboard back, and an attack costs about ten ticks, so the
# world may already have run past a turn boundary before the reading happens.
# When it has, the 3d6 turn is over before the first number is written down and
# only two drops remain to be seen; the ignition line is on that screen either
# way and the check requires it. Measured both ways: on 2026-08-24 the blow at
# tick 198117 was read at 198127, one boundary later. Nothing here tries to
# pin the phase, because the cost of an attack is not the script's to choose.
#
# WHAT IS NOT ASSERTED. Not the size of any single drop beyond an upper bound.
# 3d6 and 2d6 overlap, so a check that demanded the drops fall in order would
# fail on honest dice, and the shifting phase means no drop has a fixed die
# count. The bounds that are asserted are real: the mummy multiplies fire
# damage by 1.5 (lib/mon3.irh, "mummy"), so no single turn of this burn can
# exceed 3d6 * 1.5 = 27 and the whole burn cannot exceed 6d6 * 1.5 = 54.
# Those catch a handler that rolls the wrong number of dice or never stops.
#
# Usage: tools/check_flame_tongue_undead.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/flame-tongue-undead.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

# Pinned settings. Two runs of this check are only comparable if they played
# the same game, and the live Options.Dat is whatever Brian last used.
out="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

# A session that measured nothing must never read as a pass: inc-loa.3.
if echo "$out" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing."
    echo "$out"
    exit 1
fi
if echo "$out" | grep -q "the key script looked for something"; then
    echo "FAIL: the key script did not find a screen it expected; read"
    echo "      $run/logs/screens for the one it was looking at."
    exit 1
fi

scr="$run/logs/screens"

# The sword has to be the right sword. Wizard-mode acquisition walks a list by
# position, and a new AI_WEAPON entity in lib/m_items.irh would slide it.
wielded="$(ls "$scr"/*-wielded.txt 2>/dev/null | head -1)"
[ -n "$wielded" ] || { echo "FAIL: no wielded screen in $scr"; exit 1; }
grep -qi "Flame Tong" "$wielded" || {
    echo "FAIL: the character is not holding a flame tongue. $wielded reads:"
    sed -n '5,12p' "$wielded"
    exit 1
}

# And the blow has to have landed, or five equal readings prove only that
# nothing was hit.
struck="$(ls "$scr"/*-struck.txt 2>/dev/null | head -1)"
[ -n "$struck" ] || { echo "FAIL: no struck screen in $scr"; exit 1; }
grep -qi "hitting the mummy" "$struck" || {
    echo "FAIL: $struck shows no landed blow on the mummy."
    exit 1
}

# The dump's own HP line, not the player's status bar at the foot of the
# screen: both start with "HP:", and only the dump carries Subdual and CR.
hp_of() {
    grep -m1 '^HP:.*Subdual:.*CR:' "$1" | sed 's/^HP:\([0-9]*\)\/.*/\1/'
}

hp=()
for n in 0 1 2 3 4; do
    f="$(ls "$scr"/*-hp-$n.txt 2>/dev/null | head -1)"
    [ -n "$f" ] || { echo "FAIL: no reading $n; $scr has no *-hp-$n.txt"; exit 1; }
    grep -q "mummy (class" "$f" || {
        echo "FAIL: reading $n is not a dump of the mummy. $f reads:"
        sed -n '5,10p' "$f"
        exit 1
    }
    v="$(hp_of "$f")"
    [ -n "$v" ] || { echo "FAIL: no HP line in $f"; exit 1; }
    hp+=("$v")
done

echo
echo "mummy hit points, one reading per game turn after the blow:"
echo "  on the turn of the hit    ${hp[0]}"
for n in 1 2 3 4; do
    printf "  %d turn(s) later          %s   (fell %d)\n" \
        "$n" "${hp[$n]}" "$(( hp[$((n-1))] - hp[$n] ))"
done
echo

d=()
for n in 1 2 3 4; do
    d+=( "$(( hp[$((n-1))] - hp[$n] ))" )
done

fail=0
if [ "${d[0]}" -eq 0 ] && [ "${d[1]}" -eq 0 ] && [ "${d[2]}" -eq 0 ] && [ "${d[3]}" -eq 0 ]; then
    echo "FAIL: the mummy never burned. Its hit points did not move once in"
    echo "      four turns after a flame tongue struck it. That is PA-08-F11:"
    echo "      the sword's EITEM(EV_HIT) handler in lib/m_items.irh does"
    echo "      nothing, while its own page promises 3d6/2d6/1d6 fire damage."
    exit 1
fi

# The blow itself has to have lit the fire, and the game has to have said so.
# Without this a run that measured some other source of damage would pass.
hp0="$(ls "$scr"/*-hp-0.txt | head -1)"
# The message area is the top few lines, left of the sidebar rule, and the game
# wraps it wherever the text happens to reach, so flatten it before asking any
# question of it.
msg0="$(sed -n '2,6p' "$hp0" | sed 's/|.*$//' | tr '\n' ' ' | tr -s ' ')"
echo "$msg0" | grep -qi "catches fire" || {
    echo "FAIL: the blow printed no ignition line. $hp0 opens with:"
    echo "  $msg0"
    fail=1
}
# And whether the first of the three turns had already gone by the time that
# screen was written. When it has, its own line is on the same screen, and the
# turn is counted here rather than being lost.
early=0
echo "$msg0" | grep -qi "flesh burns" && early=1

# The burn must be a run of losing turns followed by quiet, and it must end
# inside the window. A drop that comes back after a quiet turn is a burn that
# never stops -- the failure a duration bug would produce.
seen_zero=0
burns=0
total=0
for n in 0 1 2 3; do
    v="${d[$n]}"
    if [ "$v" -lt 0 ]; then
        echo "FAIL: the mummy GAINED $(( -v )) hit points on turn $((n+1)). Something"
        echo "      other than this check is healing it; the reading is not clean."
        fail=1
    elif [ "$v" -eq 0 ]; then
        seen_zero=1
    else
        if [ "$seen_zero" -eq 1 ]; then
            echo "FAIL: the mummy burned again on turn $((n+1)) after a quiet turn."
            echo "      The page promises three consecutive turns and no more."
            fail=1
        fi
        burns=$(( burns + 1 ))
        total=$(( total + v ))
        if [ "$v" -gt 27 ]; then
            echo "FAIL: turn $((n+1)) of the burn dealt $v, above the 27 that 3d6"
            echo "      can reach even against a mummy's 1.5x fire vulnerability."
            fail=1
        fi
    fi
done

if [ "${d[3]}" -ne 0 ]; then
    echo "FAIL: the mummy was still burning on the last turn measured (it lost"
    echo "      ${d[3]}). The page promises three turns; this burn does not stop."
    fail=1
fi

# Three turns of burning, and exactly three. A turn that went by before the
# first reading is counted from its own message rather than from the numbers,
# which is what lets this be an equality and not a range.
turns=$(( burns + early ))
if [ "$turns" -ne 3 ]; then
    echo "FAIL: the burn ran for $turns turns, not the three the page promises"
    echo "      ($burns turns measured as a fall in hit points, and $early already"
    echo "      spent by the time of the first reading)."
    fail=1
fi

if [ "$total" -gt 54 ]; then
    echo "FAIL: the burn dealt $total in all, above the 54 that 3d6+2d6+1d6 can"
    echo "      reach even against a mummy's 1.5x fire vulnerability."
    fail=1
fi

[ "$fail" -eq 0 ] && printf 'PASS: a struck corporeal undead burned for three turns and then stopped\n      (%s of them measured as a fall of %s hit points in all).\n' "$burns" "$total"
exit "$fail"
