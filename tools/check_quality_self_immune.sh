#!/bin/bash
# gate: live
# fact: character -- fixture orc-mage-seed5-opt0822 (INCURSION_LOAD)
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: character level -- wizard "Free Advancement" switch, four G presses
# fact: the suit -- plain leather armour from wizard "Item Acquisition" (Item::Create, no MakeMagical)
# fact: the quality -- wizard "Add Quality to Armour", AQ_FIRE_RES (arm B only)
# fact: fire damage to the worn suit -- wizard "Burn Worn Armour" (src/Debug.cpp), fixed 10, no actor, no dice
# fact: scroll reads -- INCURSION_RUNTO_SKILL_ROLL=20 (each read totals 22, above DC 15, not above 25)
# fact: enchant limit -- level 5 plus Charisma modifier, from the fixture and the four levels
# fact: curse status -- Item::Create draws none for a plain suit (src/Term.cpp:3287)
# fact: matched text -- engine strings
# A resistance quality makes its OWN item immune, and still resists for the
# wearer (bd inc-to9x).
#
# THE RULING, made on 2026-09-11: an item of BLAH is immune to BLAH, and the
# resistance is still given to the wearer. Both halves, or the change is half
# done -- which is the failure this check exists to catch. Half one alone would
# pass a build that had silently taken the wearer's resistance away; half two
# alone would pass a build where Item::Hardness never learned the quality.
#
# TWO ARMS, ONE SEED. The character and the suit are identical in both. The
# only difference is wizard option 13 putting AQ_FIRE_RES on the worn suit
# before the burn.
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
# the function this change edits. The hit points and the item's name are the
# behavioural half.
#
# WHY THE FIRE COMES FROM A WIZARD COMMAND. A player-driven blast reaches worn
# gear only through the equipment block in Magic::Blast (src/Effects.cpp:395-421),
# whose save and coin tosses have no control. "Burn Worn Armour" (src/Debug.cpp,
# inc-aoi4i) sends a fixed 10 points of fire straight to the suit, with no actor
# and no random number. The check used to summon hell hounds for this, and the
# burn missed on seed 8.
# tools/keys/quality-self-immune-setup.keys carries the rest of that argument.
#
# WHY THE SCROLL ROLL IS FORCED. Each Enchant Armour read is a Decipher Script
# check and a high total preserves the scroll on a coin toss (src/Magic.cpp:6214).
# INCURSION_RUNTO_SKILL_ROLL=20 makes every read total 22: success, no preserve.
#
# Measured 2026-11-04 (inc-aoi4i), every seed: arm A ends at 46 of 56 hit
# points, named "mildly burnt leather armour", Fire still in its "0 to ..."
# group, no Fire on the sheet; arm B ends at 56 of 56, unburnt, Fire in its
# immunity list, and the sheet reads "Fire 6" once the suit is +2.
# tools/seed_sweep.sh: SEED-INDEPENDENT on seeds 101..505 and on 1 2 3 4 6 7 8 9.
# Usage: tools/check_quality_self_immune.sh [--prove-red]
# Declared mutation: Item::Hardness returns 0 instead of the -1 immunity.
# PROVED RED 2026-11-04, same five failures as 2026-09-11. Arm A stays green,
# which is right -- it carries no quality, so the mutation cannot reach it.
# Arm B fails five assertions (inner exit 1, outer exit 0):
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
# A frozen character, not a generated one (tools/fixtures/README.md).
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed5-opt0822.sav
export INCURSION_RUNTO_SKILL_ROLL=20
check_mutation src/Item.cpp \
'  if (QualityImmune(DType))
    return -1;' \
'  if (QualityImmune(DType))
    return 0;'

# --- ARM A: the same suit, with nothing on it ---------------------------
# inc-kbws: was seed 5; the opposed hide check (inc-u3dp) shifted the shared
# RNG stream, and the blast no longer reaches the armour on seed 5 at tip.
# Seeds 1 and 3 staged both arms then. Re-pinned 1 -> 5 for inc-rt8l (kit changes
# the random stream); seed 5 stages both arms again.
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
# Seed 5 again (inc-rt8l); see the note on arm A above.
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
