#!/bin/bash
# gate: live
# A resistance quality makes its OWN item immune, and still resists for the
# wearer (bd inc-to9x).
#
# THE RULING, made on 2026-09-11: an item of BLAH is immune to BLAH, and the
# resistance is still given to the wearer. Both halves, or the change is half
# done -- which is the failure this check exists to catch. Half one alone would
# pass a build that had silently taken the wearer's resistance away; half two
# alone would pass a build where Item::Hardness never learned the quality.
#
# TWO ARMS, ONE SEED. The character, the suit and the monsters are identical in
# both. The only difference is wizard option 13 putting AQ_FIRE_RES on the worn
# suit before the burning starts.
#
#   Arm A, tools/keys/quality-self-immune-plain.keys: no quality. The suit must
#   BURN, its page must show fewer than 56 of 56 hit points, its hardness table
#   must still count Fire among the types it resists by zero, and the character
#   sheet must show no fire resistance at all.
#
#   Arm B, tools/keys/quality-self-immune-quality.keys: AQ_FIRE_RES. The same
#   suit under the same fire must stay at 56 of 56, its hardness table must
#   count Fire among its IMMUNITIES, and -- after two Enchant Armour scrolls
#   take it to +2 -- the sheet must read "Fire 6".
#
# THE ORACLES. The suit's own page is built by ItemHardnessDesc
# (src/Help.cpp:3471-3527), which calls Item::Hardness once per damage type and
# sorts the -1 answers into "It is immune to ...". That is a direct reading of
# the function this change edits, and it needs no lucky roll. The hit points
# and the item's name are the behavioural half, and they need the blast to
# reach the armour: measured on seed 5, it does so twice in the hundred turns
# the fixture plays.
#
# WHY THE DAMAGE COMES FROM MONSTERS AND NOT A SELF-CAST SPELL. Item::Damage
# reads "If you are attacking your own items, ignore their hardness"
# (src/Item.cpp:1485-1488) and sets hard = 0, which erases the -1 immunity sentinel.
# The equipment block calls ThrowDmg, which clears isTrap and eID, so that test
# reduces to EActor == owner. A mage fireballing himself and a character
# stepping on his own trap were both measured on 2026-09-11, and both printed
# "vs. 0 (leather)" on a suit whose own page in the same session said it was
# immune to fire. Only a blast whose actor is somebody else measures anything.
# tools/keys/quality-self-immune-setup.keys carries the rest of that argument.
#
# Measured 2026-09-11, seed 5, tools/fixtures/options-2026-08-22.dat:
#   arm A ends at 43 of 56 hit points, named "mildly burnt leather armour",
#         with Fire still in its "0 to ..." group and no Fire on the sheet;
#   arm B ends at 56 of 56, unburnt, with Fire in its immunity list, and the
#         sheet reads "Fire 6" once the suit is +2.
#
# RE-CALIBRATED 2026-09-11, same day, after inc-19ay. That fix gave every breath
# weapon the dice its statblock declares, so the hounds breathe 2d6 instead of
# 1d6 and the random stream diverges at the first breath. Two numbers moved and
# neither is a property of this check: arm A's suit now ends at 43 of 56 rather
# than 52, and one of arm B's two Enchant Armour reads fell on a failed Decipher
# check, which left the suit at +1 and the sheet at "Fire 3". The answer is in
# tools/keys/quality-self-immune-quality.keys: the reader now wears a helm that
# adds +10 to Decipher Script, so a read no longer turns on a die this fixture
# cannot see. No assertion was weakened; "+2" and "Fire 6" still stand.
# Usage: tools/check_quality_self_immune.sh [--prove-red]
# Declared mutation: Item::Hardness returns 0 instead of the -1 immunity.
# PROVED RED 2026-09-11. Arm A stays green, which is right -- it carries no
# quality, so the mutation cannot reach it. Arm B fails five assertions
# (inner exit 1, outer exit 0):
#   |   FAIL  0/1 screens carry: Light Damage, Fire,
#   |         it should prove: the quality makes the suit itself immune to fire
#   |   FAIL  0/1 screens carry: It has 56 out of 56 hit
#   |         it should prove: the immune suit lost no hit points
#   |   FAIL  1/1 screens still carry: Burnt Uncursed Leather Armour
#   |         it should prove: the immune suit is not burnt
#   |   FAIL  0/1 screens carry: Light Damage, Fire,
#   |         it should prove: the immune suit is still immune after the fire
#   |   FAIL  0/1 screens carry: Leather Armour +2 Of Fire Resistance
#   |         it should prove: the scrolls took the same suit to +2
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation src/Item.cpp \
'  if (QualityImmune(DType))
    return -1;' \
'  if (QualityImmune(DType))
    return 0;'

# --- ARM A: the same suit, with nothing on it ---------------------------
check_run tools/keys/quality-self-immune-plain.keys 5
check_screens '*-burn-before'
check_expect "It has 56 out of 56 hit" "the plain suit starts undamaged"
check_expect "Disintegration, Fire." "the plain suit's hardness table counts Fire among the types it resists by zero"
check_screens '*-burn-after'
check_expect "out of 56 hit" "the plain suit's page is readable after the fire"
check_reject "It has 56 out of 56 hit" "the plain suit lost hit points"
check_expect "burnt leather armour" "the game itself calls the plain suit burnt"
check_expect "Disintegration, Fire." "the plain suit is still not immune to fire"
check_screens '*-plain-sheet'
check_expect "Resistances and Armour" "the character sheet lists resistances"
check_reject "Fire 6" "no quality, so the wearer gets no fire resistance"

# --- ARM B: the same suit, carrying AQ_FIRE_RES --------------------------
check_run tools/keys/quality-self-immune-quality.keys 5
check_screens '*-burn-before'
check_expect "Leather Armour Of Fire Resistance" "the quality is on the suit before the fire"
check_expect "Light Damage, Fire," "the quality makes the suit itself immune to fire"
check_screens '*-burn-after'
check_expect "It has 56 out of 56 hit" "the immune suit lost no hit points"
check_reject "Burnt Uncursed Leather Armour" "the immune suit is not burnt"
check_expect "Light Damage, Fire," "the immune suit is still immune after the fire"
check_screens '*-quality-item'
check_expect "Leather Armour +2 Of Fire Resistance" "the scrolls took the same suit to +2"
check_screens '*-quality-sheet'
check_expect "Fire 6" "the wearer still gets three points of fire resistance per plus"

check_done "a resistance quality protects its own item AND still resists for the wearer"
