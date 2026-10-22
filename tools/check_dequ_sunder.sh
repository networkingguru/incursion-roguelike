#!/bin/bash
# gate: live
# Does a sundering blow still cost the striker his own weapon? (bd inc-m2zi)
#
# THE RULE. A_SUND puts the VICTIM's weapon in e.EItem2, which is correct --
# that is what a sunder attacks. The response-attack loop copied e.EItem2
# forward into the A_DEQU retaliation, so sundering an ARMED equipment-
# destroying monster made its retaliation land on ITS OWN weapon, and the
# striker's weapon went free. src/Fight.cpp used to read:
#
#     it = e.EItem2;
#     if (!it)
#         it = e.EItem;
#
# and now refuses any item the responder owns before falling back to e.EItem.
#
# THE SUBJECT. The caryatid column carries A_DEQU for 12d6 AD_SHAT and a cursed
# long sword as gear (lib/mon3.irh:1646-1662). It is the only monster in lib
# that is both armed and equipment-destroying. Its armour is 20 and it
# regenerates, so a first-level character cannot kill it by accident.
#
# THE TWO WEAPONS ARE MADE DISTINGUISHABLE before anything is asserted: the
# character wields a MAUL, so "long sword" on the item page can only be the
# column's and "Maul" can only be his. The maul is iron, like the column's
# sword, so nothing but the name differs where it matters, and it is the
# heaviest ordinary weapon in lib -- 262 hit points. That matters: 12d6 against
# hardness 10 averages 32 points, and a battleaxe (26 hit points) was measured
# being destroyed outright by the first retaliation, which left no page to read.
#
# THE SAVE IS FORCED SO THE CHECK DOES NOT RIDE ON A DIE. The column's A_DEQU
# retaliation attacks the striker's maul, and the striker then rolls a Reflex
# save (src/Fight.cpp:3940); the maul only loses hit points when that save
# FAILS. On the current tree, seed 5, the maul made its save on the FIRST blow
# (the strike-1 screen read "unharmed! You avoid harm to your maul." and the
# column's sword was untouched), so a check that read only after-1 saw no
# damage and went red for a reason that had nothing to do with the fix under
# test. Appending any resource to lib/main.irc shifts the random stream on a
# pinned seed, so re-pinning would only move which run is unlucky. Instead
# INCURSION_FORCE_SAVE_ROLL=1 forces the SavingThrow die to a natural 1
# (src/Fight.cpp:401-428, consumed at src/Creature.cpp:3936-3938, and a
# natural 1 always fails per the SRD rule at src/Creature.cpp:3961-3974). The
# retaliation therefore always lands, on the first blow, every run.
#
# THE ORACLE is the maul's own description page, reached from the inventory by
# selecting the Weapon Hand and pressing 'x'. Measured on the current tree,
# seed 5, with the save forced:
#
#   before  The Uncursed Maul ('v')                  It has 262 out of 262 hit
#   after   The Mildly Damaged Uncursed Maul ('v')   It has 214 out of 262 hit
#
# Under the old behaviour the maul is untouched, because the column shattered
# its own sword instead.
#
# PROVED RED on 2026-09-10, and again on 2026-10-22 with the save forced, by
# putting the old two lines back. The inner run printed:
#
#   |   FAIL  0/1 screens carry: maul is damaged
#   |         it should prove: and the retaliation that followed named the striker's maul
#   |   FAIL  0/1 screens carry: Damaged Uncursed Maul
#   |         it should prove: the column's retaliation shattered the striker's maul
#   |   FAIL  1/1 screens still carry: It has 262 out of 262 hit
#   |         it should prove: the maul lost hit points
#   | FAIL: a sunder still turns the retaliation on the striker's own weapon
#   PROVED RED: with src/Fight.cpp mutated, this check exits 1.
#
# Usage: tools/check_dequ_sunder.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Fight.cpp \
'            it = e.EItem2;
            if (it && it->Owner() == e.EActor)
              it = NULL;
            if (!it)
                it = e.EItem;
            if (it && it->Owner() == e.EActor)
              it = NULL;' \
'            it = e.EItem2;
            if (!it)
                it = e.EItem;'

# The maul only takes damage when the striker's Reflex save against the column's
# A_DEQU retaliation fails, and that save is a die roll the check must not ride
# on (see the header). Force it to a natural 1, which always fails. The hook is
# in the shipped binary, so no probe build is needed.
export INCURSION_FORCE_SAVE_ROLL=1

check_run tools/keys/dequ-sunder.keys 5

check_screens '*-sunder-placed'
check_expect "C caryatid" \
    "an armed caryatid column stands beside the character"

check_screens '*-sunder-strike-1'
check_expect "you strike the caryatid column's" \
    "the sunder was resolved against the column's own weapon"
check_expect "maul is damaged" \
    "and the retaliation that followed named the striker's maul"

check_screens '*-sunder-before'
check_expect "The Uncursed Maul ('" \
    "the character wields a maul, which cannot be confused with a long sword"
check_expect "It has 262 out of 262 hit" \
    "and it is undamaged before the sunder"

check_screens '*-sunder-after-1'
check_expect "Damaged Uncursed Maul" \
    "the column's retaliation shattered the striker's maul"
check_reject "It has 262 out of 262 hit" \
    "the maul lost hit points"

check_done "a sunder still turns the retaliation on the striker's own weapon"
