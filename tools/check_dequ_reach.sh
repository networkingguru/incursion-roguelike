#!/bin/bash
# gate: live
# Does a reach weapon now take the retaliation it used to dodge? (bd inc-m2zi)
#
# THE RULE. A_DEQU is a response attack: striking a monster that carries one
# makes the monster counter-attack the striker's equipment. The loop in
# Creature::Strike that looks for response attacks used to be skipped whole
# unless the victim was BESIDE the striker:
#
#     if (!is_response_attk(e.AType) && e.EVictim->isBeside(e.EActor)) {
#
# So a glaive user striking from two squares away took NO retaliation from
# eleven of the thirteen monsters that carry one. The guard now lets A_DEQU
# through at any distance, and keeps the cheap early exit for everything else.
#
# THE ABSENCE OF A MESSAGE IS WHAT THE OLD BEHAVIOUR LOOKED LIKE, so every
# assertion here is a positive one. The run must show, on the same screens:
#
#   the distance    the map row reads "@.j" -- the character, one open square,
#                   the acid blob. Two squares apart, with floor between.
#   the blow        "hitting the acid blob", so a strike was resolved and not
#                   merely attempted.
#   the retaliation "Acid splashes the glaive!", the line the game prints when
#                   the ITEM is the victim of the response attack.
#   the damage      the glaive's own description page, before and after.
#
# Measured on the current tree, seed 5:
#
#   before  The Uncursed Glaive ('v')                It has 56 out of 56 hit
#   after   The Mildly Melted Uncursed Glaive ('v')  It has 49 out of 56 hit
#
# WHY A GLAIVE. It is an iron polearm carrying WT_REACH (lib/weapons.irh:192),
# so wielding it sets MS_HAS_REACH and a direction key attacks a creature two
# squares away instead of walking (src/Player.cpp:1335-1339). Its hardness
# against acid is 10 and the acid blob's A_DEQU is 2d4 with no save DC, so the
# damage it takes is also evidence that the no-save bypass ran.
#
# PROVED RED on 2026-09-10 by putting the old adjacency guard back. The inner
# run printed:
#
#   |   ok    1/3 screens: the character and the acid blob are two squares apart, floor between
#   |   ok    1/3 screens: a blow was resolved against the blob two squares away
#   |   FAIL  0/3 screens carry: Acid splashes the glaive
#   |         it should prove: the blob answered that blow by attacking the glaive
#   |   FAIL  0/1 screens carry: Melted Uncursed Glaive
#   |         it should prove: the glaive is melted after three blows
#   |   FAIL  1/1 screens still carry: It has 56 out of 56 hit
#   |         it should prove: the glaive lost hit points
#   | FAIL: a blow struck at reach still costs the striker his weapon
#   PROVED RED: with src/Fight.cpp mutated, this check exits 1.
#
# Usage: tools/check_dequ_reach.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Fight.cpp \
'if (!is_response_attk(e.AType) &&
        (e.EVictim->isBeside(e.EActor) ||
         (e.ETarget->isCreature() && e.EVictim->HasAttk(A_DEQU)))) {' \
'if (!is_response_attk(e.AType) && e.EVictim->isBeside(e.EActor)) {'

check_run tools/keys/dequ-reach.keys 5

check_screens '*-reach-strike-*'
check_expect "@.j" \
    "the character and the acid blob are two squares apart, floor between"
check_expect "hitting the acid blob" \
    "a blow was resolved against the blob two squares away"
check_expect "Acid splashes the glaive" \
    "the blob answered that blow by attacking the glaive"

check_screens '*-reach-before'
check_expect "The Uncursed Glaive ('" \
    "the character wields an ordinary glaive"
check_expect "It has 56 out of 56 hit" \
    "and it is undamaged before the first blow"

check_screens '*-reach-after'
check_expect "Melted Uncursed Glaive" \
    "the glaive is melted after three blows"
check_reject "It has 56 out of 56 hit" \
    "the glaive lost hit points"

check_done "a blow struck at reach still costs the striker his weapon"
