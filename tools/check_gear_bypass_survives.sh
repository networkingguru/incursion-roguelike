#!/bin/bash
# gate: live
# A resistance grant survives the hardness bypass, on a MUNDANE weapon (bd inc-kapn).
#
# THE RULE, ruled by the owner on 2026-09-11: a magical protection that reaches
# a bearer's gear MUST survive the hardness bypass. Asked whether a resistance
# spell should protect a plain iron sword against one of the nine no-save
# equipment-destroying monsters, he answered that the spells protect gear.
#
# THE DEFECT IT DEFENDS. src/Fight.cpp:2122 sets e.ignoreHardness whenever a
# no-save A_DEQU strikes a NON-magical item, which is the inc-m2zi ruling.
# Item::Damage used to add the owner's gear grant BEFORE honouring that flag, so
# hard = 0 threw the spell away together with the metal's own hardness. Cast
# Resist Acid, hit a magma creeper with a plain iron weapon, and the spell did
# nothing: only an IMMUNITY had any bite there, because gear == -1 returns before
# the arithmetic. The bypass is a statement about the MATERIAL -- iron does not
# resist acid -- so it may zero or halve only what Hardness() returned, and the
# grant is added after it.
#
# WHY THIS CHECK MAY USE A PLAIN MAUL WHERE ITS SIBLING COULD NOT.
# check_gear_spell_protection.sh had to buy a SILVERED MAGIC warhammer, and says
# so in its own header, for exactly this reason: under the old ordering a
# resistance was unmeasurable on any mundane item, because the bypass zeroed it.
# Measuring one on a mundane item IS the fix. So the victim here is the ordinary
# iron maul the check_dequ_* checks use -- 262 hit points, the heaviest ordinary
# weapon in lib/, so twelve retaliations cannot destroy it and leave no page to
# read -- and the bypass really does fire on it, because the maul is not magic.
#
# THE ARITHMETIC, and it is decisive rather than lucky. The magma creeper's
# A_DEQU is 3d6 AD_ACID with NO save DC (lib/mon3.irh), one of the nine, so no
# Reflex roll decides anything. Iron's acid hardness is 10 and the bypass zeroes
# it, so the number on the line is the WHOLE of the grant. "Protection from
# Acid" (lib/wspells.irh) grants 10d1 + (LEVEL_1PER1), which is 10 plus the
# caster level, and it carries EF_PROTECTS_ITEMS on the same clause that grants
# AD_ACID. CASTER LEVEL TEN gives 20. 3d6 cannot exceed 18, and 20 > 18, so no
# roll can reach the maul. Level ten is also the smallest round level that
# clears 18: the spell is level 4, so a mage needs level 7 to hold a slot at
# all, and 10 + 7 = 17 would still lose to a maximum roll.
#
# THE ORACLE is the game's own combat-numbers line in Item::Damage, which prints
# the hardness actually used, on every landed blow and with no lucky roll:
#   "Maul: 3d6 Acid = 13 vs. 20 (iron) [unhurt]"
# Before the fix that line showed the bypassed zero. The maul's hit points are
# asserted beside it, because a number on a screen is not yet an item that
# survived.
#
# Measured 2026-09-11, seed 5: the sheet reads "Acid 20", 11 of 12 strike
# screens read "vs. 20 (iron) [unhurt]" (the twelfth is the step that closes the
# distance), the maul is 262/262 before and after, and no screen reports a melt.
#
# Usage: tools/check_gear_bypass_survives.sh [--prove-red]
# THE DECLARED MUTATION restores the old ordering: it performs the addition
# above the ignoreHardness/halfHardness block and empties gear, so the statement
# below that block becomes a no-op. That is the tree as it stood this morning.
# PROVED RED; exact failing output (outer exit 0):
#   |   screens: 12 matching '*-bypass-strike-*'
#   |   FAIL  0/12 screens carry: vs. 20 (iron)
#   |         it should prove: the resistance reaches the mundane maul
#   |   FAIL  11/12 screens still carry: vs. 0 (iron)
#   |         it should prove: no blow lands on a hardness the bypass emptied
#   |         first: vs. 0 (iron)
#   |   screens: 1 matching '*-bypass-after'
#   |   FAIL  0/1 screens carry: It has 262 out of 262 hit
#   |         it should prove: the maul is undamaged after twelve blows
#   |   screens: 16 matching '*'
#   |   FAIL  11/16 screens still carry: melts
#   |         it should prove: no screen reports acid damage to the maul
#   |         first: melts
#   |
#   | FAIL: a resistance grant protects a mundane weapon through the bypass
# PROVED RED: with src/Item.cpp mutated, this check exits 1.
# The mutated run rolls the same eleven values the passing run rolls, and the
# same eleven lines read "vs. 0 (iron)" with the whole roll as damage. They sum
# to 101, and the page reads "The Partly Melted Uncursed Maul ... 161 out of 262
# hit". That is the spell doing nothing at all, which is what was reported.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation src/Item.cpp \
'        if (hard >= 0) {
            if (e.ignoreHardness == true)' \
'        if (hard >= 0) {
            hard += gear; gear = 0;
            if (e.ignoreHardness == true)'

check_run tools/keys/gear-bypass-survives.keys 5
check_screens '*-bypass-sheet'
check_expect "Resistances and Armour" "the character sheet lists resistances"
check_expect "Acid 20" "the spell's acid resistance is on the character, at 20"
check_screens '*-bypass-before'
check_expect "The Uncursed Maul ('" "the character wields an ordinary iron maul"
check_expect "It has 262 out of 262 hit" "the maul starts undamaged"
check_screens '*-bypass-strike-*'
check_expect "vs. 20 (iron)" "the resistance reaches the mundane maul"
check_reject "vs. 0 (iron)" "no blow lands on a hardness the bypass emptied"
check_screens '*-bypass-after'
check_expect "It has 262 out of 262 hit" "the maul is undamaged after twelve blows"
check_screens
check_reject "melts" "no screen reports acid damage to the maul"
check_done "a resistance grant protects a mundane weapon through the bypass"
