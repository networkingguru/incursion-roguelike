#!/bin/bash
# gate: live
# An item the owner ruled wearer-only must NOT protect gear (bd inc-w26h).
#
# THE RULE. SPELLS protect the bearer's gear; specific ITEMS do not. This is the
# negative control for check_gear_spell_protection.sh, and it is the half a
# careless edit breaks silently: adding EF_PROTECTS_ITEMS to an item costs
# nothing visible, and no other check notices. The Amulet of Bile
# (lib/m_items.irh:516) grants RESIST AD_ACID of 4 per plus and was ruled
# wearer-only, so Creature::GearResistLevel (src/Values.cpp) must hand the
# bearer's gear nothing at all.
#
# THE SECOND ASSERTION IS THE IMPORTANT ONE. An amulet that was never equipped
# would also fail to protect the gear, and the check would pass for the wrong
# reason. The character sheet must therefore show the WEARER's own acid
# resistance of 12, which is four per plus on the +3 the key script buys.
#
# WHY A SILVERED MAGIC WARHAMMER AND A MAGMA CREEPER. Both are argued in
# check_gear_spell_protection.sh, which uses the same weapon, the same monster
# and the same twelve blows. In short: a no-save A_DEQU sets ignoreHardness on a
# NON-magical item (src/Fight.cpp:2122), and since inc-kapn src/Item.cpp:1468
# zeroes only what Hardness() returned, a grant no longer needs a MAGIC victim
# to survive. The weapon is kept for its numbers: silvered, its acid hardness is
# 12, and the creeper's 3d6 reaches 18, so an unprotected hammer takes damage.
# Flag the amulet and 12 + 12 = 24 puts the hammer beyond every roll, which is
# what makes the mutation bite.
#
# THE ORACLE is the game's own combat-numbers line (src/Item.cpp:1511-1531),
# which prints the hardness AFTER GearResistLevel is added to it, and the
# hammer's own hit points.
#
# SEED-PROOFED (inc-b4l3g.18). The character is the frozen orc warrior, the map
# is its frozen scene, every blow is forced to hit and every acid roll is forced
# to a fixed value (INCURSION_FORCE_DAMAGE_ROLL=5, so the acid 3d6 reads 15).
# Unprotected, 15 beats hardness 12 by 3 on each splash, so the hammer melts;
# with the flag, hardness 24 beats every 15 and nothing melts.
#
# fact: character (race, class, stats, kit) -- tools/fixtures/specimens/orc-warrior-dequ-seed5-maxhp.sav (INCURSION_LOAD), frozen old save kept as a specimen until inc-9s4u0 gives its scene a map builder
# fact: settings -- CHECK_OPTIONS=tools/fixtures/options-2026-08-22-maxhp.dat
# fact: map and position -- the loaded save (frozen specimen, kept until inc-9s4u0), then wizard summoning
# fact: level has no other monster -- wizard Genocide Everything
# fact: creeper does not move -- wizard switch Freeze Monsters
# fact: creeper hit points -- OPT_MON_MAX_HP DOUBLE in the options file, so it outlives twelve blows
# fact: the warrior's Reflex save vs A_DEQU fails -- INCURSION_FORCE_SAVE_ROLL=1
# fact: each blow hits -- INCURSION_LOF_FORCE_ROLL=15 (hits Def 10, below a critical threat)
# fact: each acid roll -- INCURSION_FORCE_DAMAGE_ROLL=5 (acid 3d6 -> 15)
# fact: amulet +3 and hammer +2 silvered -- wizard Item Acquisition and Add Quality; Dwarven Thrower has no EF_CURSED or EF_HALF_CURSED, so MakeMagical rolls no curse (src/Item.cpp:664)
# fact: message texts -- engine strings
#
# Usage: tools/check_gear_item_exclusion.sh [--prove-red]
# INVERTED, like check_dequ_owner_immunity.sh: the mutation ADDS the flag the
# owner refused, and this check must go red because the gear stops being hurt.
# PROVED RED: add the flag; exact failing output (outer exit 0):
#   |   screens: 12 matching '*-excl-strike-*'
#   |   FAIL  only 0 of 12 screens carry: vs. 12 (silver)
#   |         it should prove: the amulet's resistance does not reach the hammer
#   |   FAIL  12/12 screens still carry: vs. 24 (silver)
#   |         it should prove: no blow meets the wearer's resistance in the gear
#   |         first: vs. 24 (silver)
#   |   screens: 16 matching '*'
#   |   FAIL  0/16 screens carry: melts
#   |         it should prove: the unprotected hammer really is damaged by the acid
#   |   screens: 1 matching '*-excl-after'
#   |   ok    1/1 screens: the hammer's page is readable after the blows
#   |   FAIL  1/1 screens still carry: It has 78 out of 65 hit
#   |         it should prove: the hammer lost hit points
#   |         first: It has 78 out of 65 hit
#   |
#   | FAIL: a wearer-only item leaves the bearer's gear exposed
#   |       the screens are in .../20261117-072739-24037-gear-item-exclusion
# PROVED RED: with lib/m_items.irh mutated, this check exits 1.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22-maxhp.dat
check_mutation lib/m_items.irh \
'AI_AMULET Effect "Bile" : EA_GRANT
  { SC_ABJ;' \
'AI_AMULET Effect "Bile" : EA_GRANT
  { Flags: EF_PROTECTS_ITEMS; SC_ABJ;'

# A frozen character, not a generated one: an rID is a POSITION (tools/fixtures/README.md).
export INCURSION_LOAD=tools/fixtures/specimens/orc-warrior-dequ-seed5-maxhp.sav
export INCURSION_FORCE_SAVE_ROLL=1
export INCURSION_LOF_FORCE_ROLL=15
export INCURSION_FORCE_DAMAGE_ROLL=5

check_run tools/keys/gear-item-exclusion.keys 5
check_screens '*-excl-sheet'
check_expect "Resistances and Armour" "the character sheet lists resistances"
check_expect "Acid 12" "the amulet is worn and protects the WEARER"
check_screens '*-excl-before'
check_expect "Uncursed Warhammer, Dwarven" "the character wields the silvered hammer"
check_expect "It has 78 out of 65 hit" "the hammer starts undamaged"
check_screens '*-excl-strike-*'
check_expect_all "vs. 12 (silver)" "the amulet's resistance does not reach the hammer"
check_reject "vs. 24 (silver)" "no blow meets the wearer's resistance in the gear"
check_screens
check_expect "melts" "the unprotected hammer really is damaged by the acid"
check_screens '*-excl-after'
check_expect "out of 65 hit" "the hammer's page is readable after the blows"
check_reject "It has 78 out of 65 hit" "the hammer lost hit points"
check_done "a wearer-only item leaves the bearer's gear exposed"
