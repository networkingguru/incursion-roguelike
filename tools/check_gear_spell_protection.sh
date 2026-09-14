#!/bin/bash
# gate: live
# A spell's SIBLING clause protects the bearer's gear (bd inc-w26h).
#
# THE RULE. SPELLS protect the bearer's gear; specific ITEMS do not. This is the
# spell half, and it defends the hardest case in lib/: "Endure the Elements"
# (lib/wspells.irh:5645) carries Flags: EF_PROTECTS_ITEMS in its FIRST clause,
# whose grant is AD_SONI, while the AD_ACID grant struck here lives in the
# fourth `and EA_INFLICT` sibling clause. lang/Grammar.acc:642-681 builds ONE
# TEffect per declaration, so every clause shares one flag array and one effect
# id; Creature::GearResistLevel (src/Values.cpp) reads the flag off the TEffect
# the stati's eID names. THIS CHECK IS THE EMPIRICAL PROOF OF THAT. Six shipped
# flags -- Eyes of Stone, Resist Water, Gauntlets of Rust, Cowl of Warding,
# Sunblade and the Girdle of the Stormlord -- rest on the same parser behaviour.
#
# WHY A SILVERED MAGIC WARHAMMER, AND NOT A PLAIN MAUL. Not because a mundane
# weapon cannot carry a grant: inc-kapn inverted the order in Item::Damage, and
# check_gear_bypass_survives.sh now measures a resistance on a plain iron maul.
# src/Fight.cpp:2122 still sets ignoreHardness whenever a no-save A_DEQU strikes
# a NON-magical item, but src/Item.cpp:1451 zeroes only what Hardness() returned
# and src/Item.cpp:1464 adds the owner's grant after it. The hammer stays
# because its bare hardness must be a number the creeper can beat: "Warhammer,
# Dwarven Thrower" arrives at its INITIAL_PLUS of +2 (lib/m_items.irh:6861);
# IQ_SILVER makes it silver, hardness 5, halved to 2 by that same quality
# (src/Item.cpp:1344), plus 5 per plus: 12.
#
# WHY A MAGMA CREEPER, AND WHY LEVEL TEN. Its A_DEQU is 3d6 AD_ACID with no save
# DC (lib/mon3.irh:2828), so no Reflex roll decides the outcome. The spell gives
# 3 + half the caster level, so 8 at level ten, and 12 + 8 = 20 is past the 18
# the dice can reach: the protection is decisive, not lucky. The bare hardness
# of 12 lets a roll of 13 or better through, which is how the mutated run bites.
#
# THE ORACLE is the game's own combat-numbers line (src/Item.cpp:1494-1514),
# which prints the hardness AFTER GearResistLevel is added to it. It needs no
# lucky roll: every landed blow prints it.
#
# Measured 2026-09-11, seed 5: flag present, 11 of 12 strike screens read
# "vs. 20 (silver)", the hammer is 78/65 before and after, and no screen reports
# a melt. Flag removed, the same 11 screens read "vs. 12 (silver)", six screens
# report a melt and the hammer ends at 61/65.
#
# ANSWER: YES. A sibling clause's grant DOES inherit the effect's flag in play.
# The 20 on the line is 12 of silvered iron plus the 8 that only the flag can
# add, and the flag is written in a clause that grants a different damage type.
#
# Usage: tools/check_gear_spell_protection.sh [--prove-red]
# PROVED RED: remove the spell's flag; exact failing output (outer exit 0):
#   |   screens: 12 matching '*-spell-strike-*'
#   |   FAIL  0/12 screens carry: vs. 20 (silver)
#   |         it should prove: the sibling clause's grant reaches the hammer
#   |   FAIL  11/12 screens still carry: vs. 12 (silver)
#   |         it should prove: no blow lands on the bare material hardness
#   |         first: vs. 12 (silver)
#   |   screens: 1 matching '*-spell-after'
#   |   FAIL  0/1 screens carry: It has 78 out of 65 hit
#   |         it should prove: the hammer is undamaged after twelve blows
#   |   screens: 16 matching '*'
#   |   FAIL  6/16 screens still carry: melts
#   |         it should prove: no screen reports acid damage to the hammer
#   |         first: melts
#   |
#   | FAIL: a sibling clause's grant protects the caster's gear
#   |       the screens are in .../20260911-145125-44454-gear-spell-protection
# PROVED RED: with lib/wspells.irh mutated, this check exits 1.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation lib/wspells.irh \
'  { Flags: EF_PROTECTS_ITEMS; SC_ABJ; IS_A_BUFF(10); Level: 4; qval: Q_TAR;' \
'  { SC_ABJ; IS_A_BUFF(10); Level: 4; qval: Q_TAR;'

check_run tools/keys/gear-spell-protection.keys 5
check_screens '*-spell-sheet'
check_expect "Resistances and Armour" "the character sheet lists resistances"
check_expect "Acid 8" "the sibling clause's acid resistance is on the character"
check_screens '*-spell-before'
check_expect "Uncursed Warhammer, Dwarven" "the character wields the silvered hammer"
check_expect "It has 78 out of 65 hit" "the hammer starts undamaged"
check_screens '*-spell-strike-*'
check_expect "vs. 20 (silver)" "the sibling clause's grant reaches the hammer"
check_reject "vs. 12 (silver)" "no blow lands on the bare material hardness"
check_screens '*-spell-after'
check_expect "It has 78 out of 65 hit" "the hammer is undamaged after twelve blows"
check_screens
check_reject "melts" "no screen reports acid damage to the hammer"
check_done "a sibling clause's grant protects the caster's gear"
