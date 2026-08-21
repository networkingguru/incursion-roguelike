#!/bin/bash
# Regression check: do the two-weapon feats reach a pair of empty hands?
#
# THE RULE. The SRD calls an unarmed strike a light weapon, so two fists are two
# light weapons and belong in the two-weapon machinery with every other pair.
# Character::HasFeat (src/Create.cpp) grants a monk Two-Weapon Style for the
# express purpose of letting him BUY Two-Weapon Tempest, and Tempest is the
# largest two-weapon payoff in the game: +10 speed, rendered on the character
# sheet as +50 percentage points. Before inc-nie the whole two-weapon block was
# gated on two Item pointers, fists are not Items, and so the feat a monk's
# fists had earned him did nothing until he put his fists away and picked up two
# nunchaku.
#
# ONE SESSION, TWO MEASUREMENTS, ONE VARIABLE: the character buys Tempest
# between them, and the Brawl row of the character sheet is read either side.
#
#   Monk 1 / Warrior 9,  no Tempest -> Speed 125% (base 100% +25% Warrior)
#   Monk 1 / Warrior 10, Tempest    -> Speed 175% (... +50% dual-weapon)
#
# A warrior's own speed contribution does not move between those two levels, so
# the whole of the 50 points is the feat.
#
# AND A REGRESSION GUARD, which is the more important half. inc-dzz gave a monk
# a second fist striking at 0/0 with full Strength, and inc-nie changed HOW that
# happens -- the second fist now reads the off-hand attributes rather than being
# exempted from the secondary-natural-attack penalties by hand. The sidebar at
# 1st level must therefore still read two Punch lines, equal to-hit numbers
# either side of the slash, and the same damage on both.
#
# WHAT THIS CHECK CANNOT SHOW, and it is worth knowing: a character who fights
# with two fists and does NOT hold the two-weapon feats cannot be built in the
# game. src/Create.cpp grants Two-Weapon Style and Ambidexterity to anyone with
# CA_UNARMED_STRIKE, and Creature::TwoFistFighting() requires CA_UNARMED_STRIKE,
# so the two conditions are the same condition. That half of the rule was proved
# with a probe build instead; see the inc-nie row in docs/REPORTING-GATE.md.
#
# Usage: tools/check_two_fist_feats_live.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/monk-tempest.keys
WANT_BEFORE=125
WANT_AFTER=175

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
    echo "FAIL: the key script did not find a screen it expected. Most likely the"
    echo "      level-up menu never offered 'Two-Weapon Tempes' -- feat names are"
    echo "      truncated to 18 characters there. Read $run/logs/screens."
    exit 1
fi

sidebar="$run/logs/screens/0001-sidebar-monk1.txt"
before="$run/logs/screens/0002-sheet-before.txt"
after="$run/logs/screens/0003-sheet-after.txt"

for f in "$sidebar" "$before" "$after"; do
    [ -f "$f" ] || { echo "FAIL: no screen dump at $f"; exit 1; }
done

fail=0

# --- the regression guard, first ------------------------------------------
# Two fists, or this character is not fighting the way the check assumes and
# every number below it is about something else.
punches="$(grep -c "Punch:" "$sidebar")"
hitline="$(grep -o "Hit:[0-9-]* / [0-9-]*" "$sidebar" | head -1)"
mainhit="$(echo "$hitline" | sed 's/Hit:\([0-9-]*\) .*/\1/')"
offhit="$(echo "$hitline" | sed 's/.*\/ \([0-9-]*\)/\1/')"
dmgcount="$(grep "Punch:" "$sidebar" | sort -u | wc -l | tr -d ' ')"

echo
echo "Monk 1 sidebar: $hitline, $punches Punch lines, $dmgcount distinct damage line(s)"

if [ "$punches" -ne 2 ]; then
    echo "FAIL: the sidebar shows $punches Punch lines, not 2. Either the second"
    echo "      fist is gone (inc-dzz regressed) or this race fights with natural"
    echo "      attacks instead -- Creature::ListAttacks prefers them when"
    echo "      OPT_MONK_MODE is 0, and then no fist is measured at all."
    fail=1
fi
if [ -z "$hitline" ]; then
    echo "FAIL: the sidebar shows no 'Hit:x / y' line to read."
    fail=1
elif [ "$mainhit" != "$offhit" ]; then
    echo "FAIL: the two fists strike at $mainhit / $offhit, not 0/0. A monk holds"
    echo "      Two-Weapon Style and Ambidexterity, so both fists should be equal."
    fail=1
fi
if [ "$dmgcount" -ne 1 ]; then
    echo "FAIL: the two fists do different damage. The off hand should get full"
    echo "      Strength -- the SRD gives a monk no off-hand attack unarmed."
    fail=1
fi

# --- the feat itself -------------------------------------------------------
# The Brawl block is three lines; other modes have a Speed line too, so anchor
# on the Brawl heading and take the Speed line that follows it.
brawl_speed() {
    awk '/^ Brawl /{f=1} f && /Speed/{print; exit}' "$1" \
        | grep -o '[0-9][0-9]*%' | head -1 | tr -d '%'
}

got_before="$(brawl_speed "$before")"
got_after="$(brawl_speed "$after")"

grep -q "Warrior 9"  "$before" || { echo "FAIL: $before is not the Warrior 9 sheet"; fail=1; }
grep -q "Warrior 10" "$after"  || { echo "FAIL: $after is not the Warrior 10 sheet"; fail=1; }

echo "Brawl speed, bare hands, before buying Two-Weapon Tempest: ${got_before:-<none>}%"
echo "Brawl speed, bare hands, after  buying Two-Weapon Tempest: ${got_after:-<none>}%"

if [ "${got_before:-}" != "$WANT_BEFORE" ]; then
    echo "FAIL: before the feat the Brawl row should read ${WANT_BEFORE}%."
    fail=1
fi
if [ "${got_after:-}" != "$WANT_AFTER" ]; then
    echo "FAIL: after the feat the Brawl row should read ${WANT_AFTER}%."
    echo "      This is the defect inc-nie fixed: the two-weapon block is gated"
    echo "      on two Item pointers in Creature::CalcValues, and fists are not"
    echo "      Items, so Tempest reaches nothing with empty hands."
    fail=1
fi
# And the bonus must be named on the sheet, not merely arrive as a number, so a
# coincidence somewhere else in the speed stack cannot pass this.
if ! awk '/^ Brawl /{f=1} f && /Speed/{print; exit}' "$after" | grep -q "dual-weapon"; then
    echo "FAIL: the Brawl row's breakdown does not name a dual-weapon bonus, so"
    echo "      whatever moved the number, it was not the two-weapon block."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo
    echo "PASS: two fists still strike at ${mainhit}/${offhit} with one damage line, and"
    echo "      Two-Weapon Tempest moves bare-handed speed ${got_before}% -> ${got_after}%."
fi
exit "$fail"
