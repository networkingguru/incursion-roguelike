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
# NON-magical item (src/Fight.cpp:2122), and since inc-kapn src/Item.cpp:1451
# zeroes only what Hardness() returned, a grant no longer needs a MAGIC victim
# to survive. The weapon is kept for its numbers: silvered, its acid hardness is
# 12, and the creeper's 3d6 reaches 18, so an unprotected hammer takes damage.
# Flag the amulet and 12 + 12 = 24 puts the hammer beyond every roll, which is
# what makes the mutation bite.
#
# THE ORACLE is the game's own combat-numbers line (src/Item.cpp:1494-1514),
# which prints the hardness AFTER GearResistLevel is added to it, and the
# hammer's own hit points.
#
# Measured 2026-09-11, seed 5: flag absent, 11 of 12 strike screens read
# "vs. 12 (silver)", two report the hammer melting, and it ends at 75/65 from
# 78/65. Flag added, the same 11 read "vs. 24 (silver)", nothing melts and the
# hammer ends at 78/65.
# Usage: tools/check_gear_item_exclusion.sh [--prove-red]
# INVERTED, like check_dequ_owner_immunity.sh: the mutation ADDS the flag the
# owner refused, and this check must go red because the gear stops being hurt.
# PROVED RED: add the flag; exact failing output (outer exit 0):
#   |   screens: 12 matching '*-excl-strike-*'
#   |   FAIL  0/12 screens carry: vs. 12 (silver)
#   |         it should prove: the amulet's resistance does not reach the hammer
#   |   FAIL  11/12 screens still carry: vs. 24 (silver)
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
#   |       the screens are in .../20260911-145216-47402-gear-item-exclusion
# PROVED RED: with lib/m_items.irh mutated, this check exits 1.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation lib/m_items.irh \
'AI_AMULET Effect "Bile" : EA_GRANT
  { SC_ABJ;' \
'AI_AMULET Effect "Bile" : EA_GRANT
  { Flags: EF_PROTECTS_ITEMS; SC_ABJ;'

check_run tools/keys/gear-item-exclusion.keys 5
check_screens '*-excl-sheet'
check_expect "Resistances and Armour" "the character sheet lists resistances"
check_expect "Acid 12" "the amulet is worn and protects the WEARER"
check_screens '*-excl-before'
check_expect "Uncursed Warhammer, Dwarven" "the character wields the silvered hammer"
check_expect "It has 78 out of 65 hit" "the hammer starts undamaged"
check_screens '*-excl-strike-*'
check_expect "vs. 12 (silver)" "the amulet's resistance does not reach the hammer"
check_reject "vs. 24 (silver)" "no blow meets the wearer's resistance in the gear"
check_screens
check_expect "melts" "the unprotected hammer really is damaged by the acid"
check_screens '*-excl-after'
check_expect "out of 65 hit" "the hammer's page is readable after the blows"
check_reject "It has 78 out of 65 hit" "the hammer lost hit points"
check_done "a wearer-only item leaves the bearer's gear exposed"
