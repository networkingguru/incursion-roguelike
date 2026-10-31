#!/bin/bash
# gate: live
# A Craft repair MUST cost more gold the more damaged the item is (bd inc-nc1).
#
# THE DEFECT. Character::CraftItem (src/Skills.cpp), Repair branch, priced the
# materials as shopCost * tenths-of-HP-LEFT / 30. The DC line above it adds the
# complementary tenths of HP LOST. The cost line lacked the "10 -", so a
# nearly destroyed item cost almost nothing and a scratched one cost the most.
#
# THE ORACLE is the game's own text, no probe. A frozen paladin whose leather
# armour +3 is already damaged is loaded. Three screens give the facts: the
# item's description ("base value of S gp", "H out of M hit points"), the
# "Repair which item?" menu ("(H/M)"), and the repair's own "That would cost N
# gp in materials" message. The engine's integer arithmetic is repeated here:
# lost = 10 - (H*10)/M, expected N = S * lost / 30. The check FAILS (exit 2)
# when a screen or number is missing, so it cannot pass by never reaching the
# code.
#
# fact: the character, a human paladin wearing leather armour +3 -- frozen save human-paladin-damaged-armour-opt0822.sav, loaded (INCURSION_LOAD)
# fact: the armour's damage, below its maximum hit points -- frozen in that save; no trap or roll runs here, and the check dies (exit 2) when H >= M
# fact: the armour's base value S -- read from the examine screen, not typed here
# fact: the armour's hit points H and M -- read from the examine screen and checked against the repair menu
# fact: the repair price N -- read from the "That would cost N gp in materials" message
# fact: the settings -- tools/fixtures/options-2026-08-22.dat via CHECK_OPTIONS
# fact: the seed -- irrelevant to the price (no roll between load and the cost message); pinned only so the run is repeatable
# fact: the gold carried, 11 gp -- frozen in the save; the repair stops at the message, spending nothing
# fact: the screen texts (exam, menu, cost) -- the keys dump them, and the check dies (exit 2) when one is missing
# fact: lost = 5 tenths cannot tell the two formulas apart -- the check dies (exit 2) on it
#
# Usage: tools/check_repair_cost.sh
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

SEED=1
KEYS=tools/keys/repair-cost.keys
LOAD=tools/fixtures/chars/human-paladin-damaged-armour-opt0822.sav

[ -f "$LOAD" ] || _check_die 2 \
    "no $LOAD, so there is no frozen paladin with damaged leather armour +3."

export INCURSION_RUN_DIR="$CHECK_ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-repair-cost"
export INCURSION_LOAD="$LOAD"

check_run "$KEYS" "$SEED"
check_screens

SCR="$CHECK_RUN/logs/screens"
EXAM="$(ls "$SCR"/*-exam.txt 2>/dev/null | head -1)"
MENU="$(ls "$SCR"/*-menu.txt 2>/dev/null | head -1)"
COST="$(ls "$SCR"/*-cost.txt 2>/dev/null | head -1)"
[ -f "$EXAM" ] && [ -f "$MENU" ] && [ -f "$COST" ] || _check_die 2 \
    "the session did not dump the exam, menu and cost screens."

BASE="$(grep -o 'base value of [0-9]* gp' "$EXAM" | head -1 | grep -o '[0-9]*')"
HP="$(grep -o 'has [0-9]* out of [0-9]* hit' "$EXAM" | head -1 | grep -o '[0-9]*' | sed -n 1p)"
MAX="$(grep -o 'has [0-9]* out of [0-9]* hit' "$EXAM" | head -1 | grep -o '[0-9]*' | sed -n 2p)"
GOLD="$(grep -o 'That would cost [0-9]* gp in materials' "$COST" | head -1 | grep -o '[0-9]*')"
MENUHP="$(grep -o 'leather armour +3 ([0-9]*/[0-9]*)' "$MENU" | head -1)"

[ -n "$BASE" ] && [ -n "$HP" ] && [ -n "$MAX" ] && [ -n "$GOLD" ] || _check_die 2 \
    "could not read the base value, hit points or repair cost from the screens" \
    "(base='$BASE' hp='$HP' max='$MAX' cost='$GOLD')."
[ "$MENUHP" = "leather armour +3 ($HP/$MAX)" ] || _check_die 2 \
    "the repair menu item ('$MENUHP') is not the examined armour ($HP/$MAX)."
[ "$HP" -lt "$MAX" ] || _check_die 2 "the armour is undamaged ($HP/$MAX), so nothing was measured."

LOST=$((10 - (HP * 10) / MAX))
[ "$LOST" -ne 5 ] || _check_die 2 "damage of 5 tenths cannot tell the two formulas apart."
EXPECT=$((BASE * LOST / 30))
echo "  armour $HP/$MAX hit points, base value $BASE gp, repair cost $GOLD gp, expected $EXPECT gp"

if [ "$GOLD" -eq "$EXPECT" ]; then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    the repair price follows the tenths of damage"
else
    echo "  FAIL  repair price $GOLD gp, expected $EXPECT gp ($BASE gp * $LOST/10 lost / 3)"
    CHECK_FAIL=1
fi

check_done "a Craft repair costs more gold the more damaged the item is"
