#!/bin/bash
# Regression check for the consumable that was spent on an action that never
# happened, bd inc-bp2.
#
# WHAT IS BEING PROVED. Item::DrinkPotion and Item::ReadScroll (src/Magic.cpp)
# both begin by calling Item::TakeOne(), which takes the unit OUT of the pack
# before the effect has run, and both used to end with an unconditional
# Remove(true). Every path that left early therefore threw the unit away:
# reading a scroll and then accepting the game's own offer to stop cost a
# scroll, and an EV_EFFECT that returned ABORT cost the potion. Food::Eat had
# the same shape and the same defect (inc-i9q.1, src/Item.cpp); its fix was to
# route the refusal through a branch that gives the unit back.
#
# The oracle is the scroll, not the potion, and that is deliberate. The potion
# half of inc-bp2 cannot be driven from the keyboard: with the effects lib/
# ships today, no AI_POTION effect returns ABORT from EV_EFFECT, and the one
# potion prompt a player can escape (Player::UseItemMenu asks for the target
# BEFORE throwing EV_DRINK) never reaches DrinkPotion at all. The scroll's
# "Stop reading?" is the same function shape, is two keystrokes away, and is
# the branch a player actually meets.
#
# Measured on seed 5, tools/keys/consumable-abort.keys, src/Magic.cpp,
# src/Item.cpp and inc/Item.h the only files different between the two builds:
#
#   answer yes to "Stop reading?"   before: 3 Scrolls of Wizard Sight -> 2
#                                   after:  3 Scrolls of Wizard Sight -> 3
#   drink a Potion of Healing       before: 2 Potions of Healing -> 1
#                                   after:  2 Potions of Healing -> 1
#
# The second measurement is not decoration. It is the half that fails if a
# "fix" simply stops consuming things, which would pass the first half while
# making every potion in the game infinite.
#
# THE RUN CAN FAIL TO MEASURE ANYTHING, and that is reported as INCONCLUSIVE
# rather than FAIL. The "Stop reading?" offer only appears after a successful
# Will save; a session that never saw it says nothing about the bug, and so
# does a session whose wizard-mode acquisitions landed on the wrong list row.
# Sending somebody hunting a regression that a dead session invented is the
# mistake of inc-loa.3.
#
# Usage: tools/check_consumable_abort.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=5
SCROLLS="3 Scrolls of Wizard Sight"
POTIONS="2 Potions of Healing"
ONE_POTION="Potion of Healing"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/consumable-abort.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
S="$run/logs/screens"

for f in 0001-pack-before 0002-offer 0003-pack-refused 0004-pack-quaffed; do
    [ -f "$S/$f.txt" ] || {
        echo "INCONCLUSIVE: the session produced no $f screen. Run dir: $run"
        exit 2
    }
done

# Did wizard mode hand over the two consumables this check is about? The
# acquisition list has no menu letters, so the key script counts DOWN presses
# into a list that lib/ builds; a new potion or scroll effect shifts it.
grep -q "$SCROLLS" "$S/0001-pack-before.txt" || {
    echo "INCONCLUSIVE: the pack does not hold \"$SCROLLS\" before the test."
    echo "              The DOWN counts in the key script have probably drifted."
    echo "              Run dir: $run"
    exit 2
}
grep -q "$POTIONS" "$S/0001-pack-before.txt" || {
    echo "INCONCLUSIVE: the pack does not hold \"$POTIONS\" before the test."
    echo "              The DOWN counts in the key script have probably drifted."
    echo "              Run dir: $run"
    exit 2
}

# Was the refusal ever offered? Without this the check cannot tell a scroll
# that survived a refusal from a run where no refusal was ever possible.
grep -q "Stop reading?" "$S/0002-offer.txt" || {
    echo "INCONCLUSIVE: the game never offered \"Stop reading?\", so the run"
    echo "              never refused anything. The Will save behind that offer"
    echo "              is seed-sensitive; see the key script's header."
    echo "              Run dir: $run"
    exit 2
}

fail=0

# 1. The refusal must cost nothing.
if ! grep -q "$SCROLLS" "$S/0003-pack-refused.txt"; then
    echo "FAIL: after answering yes to \"Stop reading?\" the pack no longer holds"
    echo "      \"$SCROLLS\" -- refusing to read spent a scroll."
    grep -m1 "Scrolls* of Wizard Sight" "$S/0003-pack-refused.txt" |
        sed 's/^/      now: /'
    fail=1
fi
if ! grep -q "$POTIONS" "$S/0003-pack-refused.txt"; then
    echo "FAIL: the refused read also changed the potion count, which nothing"
    echo "      in that path should touch."
    fail=1
fi

# 2. Using a consumable must still spend it.
if grep -q "$POTIONS" "$S/0004-pack-quaffed.txt"; then
    echo "FAIL: a Potion of Healing was quaffed and the pack still holds"
    echo "      \"$POTIONS\" -- consumables are no longer being spent."
    fail=1
elif ! grep -q "$ONE_POTION" "$S/0004-pack-quaffed.txt"; then
    echo "FAIL: after quaffing one of two Potions of Healing the pack holds"
    echo "      neither two nor one of them."
    fail=1
fi

if [ "$fail" = 1 ]; then
    echo "Run dir: $run"
    exit 1
fi

echo "PASS: a refused read keeps its scroll, and a drunk potion is still spent."
echo "Run dir: $run"
exit 0
