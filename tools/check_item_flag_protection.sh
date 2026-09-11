#!/bin/bash
# Bracers of Neutralization protect gear through EF_PROTECTS_ITEMS (inc-w26h).
# Acid is not blanket: the bracers' flag is the only route to the iron maul.
# Acid blob (lib/mon3.irh) is a summonable low-CR jelly with 2d4 AD_ACID A_DEQU,
# blunt resistance, and low damage. Frozen monsters still retaliate on a hit;
# acid immunity protects the level-one bearer, and 262 maul HP permits rereading.
# The sheet must show acid immunity; the maul must be 262/262 before and after.
# Usage: tools/check_item_flag_protection.sh [--prove-red]
# Measured 2026-09-10: flag present 262/262 HP; flag removed 241/262 HP.
# PROVED RED: remove only the Neutralization flag; exact failing output:
#   |   FAIL  0/1 screens carry: It has 262 out of 262 hit
#   |         it should prove: the flagged grant protects the maul after five blows
#   | 
#   | FAIL: flagged acid immunity protects the owner's maul
#   |       the screens are in /Users/brianhill/Scripts/Incursion-w26h/logs/runs/20260910-203442-81868-item-flag-protection/logs/screens
# PROVED RED: with lib/m_items.irh mutated, this check exits 1.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation lib/m_items.irh \
'AI_BRACERS Effect "Neutralization" : EA_GRANT
  { Flags: EF_PROTECTS_ITEMS; SC_ABJ; Level: 10;' \
'AI_BRACERS Effect "Neutralization" : EA_GRANT
  { SC_ABJ; Level: 10;'

check_run tools/keys/item-flag-protection.keys 5
check_screens '*-flag-sheet'
check_expect "Complete Immunities:" "the character sheet lists immunities"
check_expect "Acid" "acid immunity is active on the character"
check_screens '*-flag-before'
check_expect "The Uncursed Maul ('" "the character wields an ordinary iron maul"
check_expect "It has 262 out of 262 hit" "the maul starts undamaged"
check_screens '*-flag-after'
check_expect "It has 262 out of 262 hit" "the flagged grant protects the maul after five blows"
check_done "flagged acid immunity protects the owner's maul"
