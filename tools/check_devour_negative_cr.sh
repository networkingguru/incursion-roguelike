#!/bin/bash
# Regression check for the experience an orc gets from eating a corpse whose
# challenge rating is below zero, bd inc-i9p.
#
# WHAT IS BEING PROVED, AND WHAT WAS NOT. The bead reported an experience LOSS.
# Creature::DevourMonster (src/Skills.cpp) ends with
#
#     i = CR * 50;
#     for (j = ChallengeRating(); j >= CR; j--) i /= 2;
#     GainXP(i);
#
# i and j are int16 and Character::GainXP takes a uint32 (src/Create.cpp), so a
# negative i would arrive as a huge unsigned number and would subtract points
# instead of adding them. A myconid is written "CR: -2" in lib/mon2.irh, which
# made the loss look certain.
#
# It does not happen, and this check is what settled that. Creature::
# ChallengeRating (src/Creature.cpp) is declared
# "int16 ChallengeRating(bool allow_neg = false)" and ends "return max(0,CR)".
# DevourMonster calls it with no argument, so a CR -2 corpse arrives here as
# ZERO, the award is 0 * 50 = 0, and nothing negative ever reaches GainXP. The
# clamp is load-bearing and undocumented, which is why it is worth a check: a
# later hand that "fixed" the clamped call to ChallengeRating(true) would open
# the very hole the bead described.
#
# THE ORACLE IS THE GAME'S OWN EXPERIENCE COUNTER, written into the status
# sidebar as "<n>/<next> XP" (src/Term.cpp:369) and read off four dumped
# screens. Measured on seed 4, tools/keys/devour-negative-cr.keys:
#
#   kill a myconid (CR -2)      0 -> 67 XP
#   eat its corpse             67 -> 67 XP     award 0, and never negative
#   kill a tabaxi (CR 2)       67 -> 317 XP
#   eat its corpse            317 -> 417 XP     award 100 = 2 * 50
#
# The 67 for the myconid kill is itself a second reading of the same clamp.
# Character::KillXP (src/Create.cpp) switches on the victim's
# ChallengeRating(): case 0 pays 75 and case -2 pays 35, and 75 * 90 / 100 is
# 67 while 35 * 70 / 100 is 24. The game paid 67, so it saw a CR of 0.
#
# THE TABAXI IS THE CONTROL AND IT IS NOT DECORATION. An unchanged number
# proves nothing on its own: a character with no Devouring ability, or a
# DevourMonster that returned before its last block, would read exactly the
# same. The tabaxi stands at CR 2 against a 1st-level devourer, so the halving
# loop never runs and the award is the whole 100 points. If that award is
# missing, this session did not exercise the arithmetic and its myconid reading
# says nothing.
#
# A RUN THAT MEASURED NOTHING IS INCONCLUSIVE, NOT A PASS AND NOT A FAILURE.
# The session drives two wizard-mode summon menus and two menu choices by name;
# a monster renamed in lib/, or a group renamed in src/Tables.cpp, stops the
# key script rather than measuring something else. Sending somebody hunting a
# regression that a dead session invented is the mistake of inc-loa.3.
#
# Usage: tools/check_devour_negative_cr.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=4
ATE_NEG="You finish eating the myconid corpse"
ATE_POS="You finish eating the tabaxi corpse"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# The pinned options file, not the live one: the live Options.Dat is whatever
# the owner last played with and the game rewrites it every session, which has
# already moved a screen out from under a comparison once (tools/README.md,
# trap 2).
out="$(INCURSION_OPTIONS=tools/gates/Options.Dat \
       tools/headless.sh tools/keys/devour-negative-cr.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
S="$run/logs/screens"

if echo "$out" | grep -qE 'NO GAMEPLAY|the key script looked for something'; then
    echo "INCONCLUSIVE: the session did not complete its measurement."
    echo "$out"
    exit 2
fi

for f in 0001-xp-before-myconid 0002-xp-after-myconid 0003-log-myconid \
         0004-xp-before-tabaxi  0005-xp-after-tabaxi  0006-log-tabaxi; do
    [ -f "$S/$f.txt" ] || {
        echo "INCONCLUSIVE: the session produced no $f screen. Run dir: $run"
        exit 2
    }
done

# The sidebar's own number, off each screen.
readxp() {
    grep -o '|[0-9]*/[0-9]* XP' "$1" | head -1 | tr -d '|' | cut -d/ -f1
}

before_neg="$(readxp "$S/0001-xp-before-myconid.txt")"
after_neg="$(readxp  "$S/0002-xp-after-myconid.txt")"
before_pos="$(readxp "$S/0004-xp-before-tabaxi.txt")"
after_pos="$(readxp  "$S/0005-xp-after-tabaxi.txt")"

for v in "$before_neg" "$after_neg" "$before_pos" "$after_pos"; do
    case "$v" in
        ''|*[!0-9]*)
            echo "INCONCLUSIVE: the status sidebar did not print a readable XP"
            echo "              count on all four screens. Run dir: $run"
            exit 2
            ;;
    esac
done

# Did the session get as far as killing anything? Without a kill there is no
# character to devour with and no number to compare.
if [ "$before_neg" -le 0 ]; then
    echo "INCONCLUSIVE: the character had no experience before the first meal,"
    echo "              so the myconid was never killed and nothing was"
    echo "              measured. Run dir: $run"
    exit 2
fi

fail=0

# 1. The meal must have happened. A build that never devours anything would
#    pass every arithmetic test below by doing nothing at all.
if ! grep -qF "$ATE_NEG" "$S/0003-log-myconid.txt"; then
    echo "FAIL: the message log never says \"$ATE_NEG\"."
    echo "      Nothing was devoured, so the XP reading below is empty."
    fail=1
fi
if ! grep -qF "$ATE_POS" "$S/0006-log-tabaxi.txt"; then
    echo "FAIL: the message log never says \"$ATE_POS\"."
    echo "      The control meal did not happen."
    fail=1
fi

# 2. Eating a corpse of negative challenge rating must not COST experience.
if [ "$after_neg" -lt "$before_neg" ]; then
    echo "FAIL: devouring the CR -2 myconid took experience away."
    echo "      before: $before_neg XP    after: $after_neg XP"
    echo "      A negative award has reached Character::GainXP, which takes a"
    echo "      uint32; check the clamp in Creature::ChallengeRating."
    fail=1
fi

# 3. The control: the award path must still be alive, or test 2 proves nothing.
if [ "$after_pos" -le "$before_pos" ]; then
    echo "FAIL: devouring the CR 2 tabaxi paid nothing."
    echo "      before: $before_pos XP    after: $after_pos XP"
    echo "      DevourMonster is not awarding experience at all, so the"
    echo "      myconid reading above measures nothing."
    fail=1
fi

if [ "$fail" = 1 ]; then
    echo "Run dir: $run"
    exit 1
fi

echo "PASS: eating a CR -2 myconid moved experience $before_neg -> $after_neg"
echo "      (no loss), and the CR 2 control paid $before_pos -> $after_pos."
echo "Run dir: $run"
exit 0
