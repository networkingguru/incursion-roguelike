#!/bin/bash
# Regression check: does an unarmed strike meet Weapon Immunity at all, and does
# Ki Strike get through it?
#
# The rule Help.cpp:2060 states to the player is that the creature "is
# unaffected by weapons with a plus less than N". The engine tests that in
# exactly one place, src/Fight.cpp inside Creature::Damage, and that test used
# to be gated on a hand-written list of seven attack types with A_PUNC, A_CLAW
# and A_BITE absent from it. A fist therefore never met the rule -- not beaten,
# never asked.
#
# One session, two measurements, one variable between them: the character's
# level, and so whether he carries Ki Strike.
#
#   Monk 1, no Ki Strike, bare fist  -> "Your weapon fails to penetrate."
#   Monk 4, Ki Strike +1, same fist  -> that line is gone and the devil reels.
#
# The subject is a lemure, a CR 1 devil with ABILITY(CA_WEAPON_IMMUNITY,1)
# (lib/mon4.irh:1205-1213), summoned beside the player in wizard mode. Immunity
# level 1 is what makes the pair of measurements sharp: Ki Strike +1 is exactly
# enough and nothing is exactly not enough.
#
# The oracle line is printed at src/Fight.cpp:8510 when e.isWImmune is set, and
# nowhere else in the game.
#
# ON A BUILD WITHOUT THE FIX both halves read the same: the Monk 1 punch lands
# with no failure line, because the fist never reached the test. That is the
# defect, and it is why the first assertion below is the load-bearing one.
#
# Usage: tools/check_weapon_immunity_live.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/monk-weapon-immunity.keys
IMMUNE_LINE="fails to penetrate"

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
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

summon="$run/logs/screens/0001-summoned-lvl1.txt"
lvl1="$run/logs/screens/0002-punch-lvl1.txt"
lvl4="$run/logs/screens/0003-punch-lvl4.txt"

for f in "$summon" "$lvl1" "$lvl4"; do
    [ -f "$f" ] || { echo "FAIL: no screen dump at $f"; exit 1; }
done

# The message area is the top few lines, left of the sidebar rule, and the game
# wraps it at whatever column the text happens to reach. A phrase can therefore
# be split across two screen lines, and it splits at a DIFFERENT place on a
# build that prints one more sentence -- which is exactly the build this check
# is comparing against. So flatten it to one line before asking any question of
# it. Grepping the raw dump for a phrase is what made the first version of this
# check pass and fail for the wrong reasons.
msgtext() {
    sed -n '2,6p' "$1" | sed 's/|.*$//' | tr '\n' ' ' | tr -s ' '
}

# The devil has to be there, or "no failure message" proves only that nothing
# was hit. The summoned lemure stands one square east of the player, drawn as
# the glyph pair @o.
grep -q "@o" "$summon" || {
    echo "FAIL: $summon does not show the summoned lemure beside the player."
    echo "      Wizard-mode summoning did not place it; nothing was punched."
    exit 1
}
# And the punch has to have connected, on both sides, or the comparison is
# between two misses.
for f in "$lvl1" "$lvl4"; do
    msgtext "$f" | grep -qi "you punch, hitting the lemure" || {
        echo "FAIL: $f shows no landed punch on the lemure. Its message area reads:"
        msgtext "$f"
        exit 1
    }
done

echo
if msgtext "$lvl1" | grep -qi "$IMMUNE_LINE"; then
    echo "Monk 1, bare fist:  '$IMMUNE_LINE' present   <- the rule was applied"
    got1=yes
else
    echo "Monk 1, bare fist:  '$IMMUNE_LINE' ABSENT    <- the fist bypassed the rule"
    got1=no
fi
if msgtext "$lvl4" | grep -qi "$IMMUNE_LINE"; then
    echo "Monk 4, Ki Strike:  '$IMMUNE_LINE' present   <- Ki Strike did not get through"
    got4=yes
else
    echo "Monk 4, Ki Strike:  '$IMMUNE_LINE' absent    <- Ki Strike got through"
    got4=no
fi

fail=0
if [ "$got1" != yes ]; then
    echo
    echo "FAIL: a mundane bare fist damaged a creature with Weapon Immunity 1"
    echo "      without ever being tested against it. That is inc-bei: the"
    echo "      attack-type gate in Creature::Damage does not admit A_PUNC."
    fail=1
fi
if [ "$got4" != no ]; then
    echo
    echo "FAIL: a Monk 4's Ki Strike +1 did not beat Weapon Immunity 1."
    echo "      Either the CA_KI_STRIKE branch beside that gate is commented out"
    echo "      again, or lib/classes.irh no longer grants the ability and"
    echo "      mod/Incursion.Mod needs rebuilding (see check_ki_strike_live.sh)."
    fail=1
fi

[ "$fail" -eq 0 ] && echo && echo "PASS: a mundane fist is stopped by Weapon Immunity 1; Ki Strike +1 beats it."
exit "$fail"
