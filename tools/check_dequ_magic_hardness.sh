#!/bin/bash
# gate: live
# Does a magical weapon still survive what a plain one no longer does? (bd inc-m2zi)
#
# THE RULE. A_DEQU is a response attack: striking a monster that carries one
# makes the monster counter-attack the striker's equipment. Nine of the
# thirteen monsters that carry it have lost their saving throw. Against those
# nine a NON-MAGICAL item now has its hardness BYPASSED and takes the whole
# roll; a MAGICAL item keeps its hardness and takes nothing it could not take
# before. src/Fight.cpp:
#
#     e2.ignoreHardness = (e2.saveDC <= 0 && !it->isMagic());
#
# THE SUBJECT. The acid blob's A_DEQU is 2d4 AD_ACID with no DC
# (lib/mon3.irh:2585). An ordinary iron weapon has hardness 10 and 2d4 cannot
# exceed 8, so before this change the blob could never scratch one. That makes
# the plain long sword the sharpest possible before/after: untouched under the
# old rule, melted under the new one.
#
# THE ORACLE is the weapon's own description page, reached from the inventory
# by selecting the Weapon Hand and pressing 'x'. It names the wear in its title
# and states the hit points in its Composition paragraph. Measured on the
# current tree, seed 5:
#
#   plain  before  The Uncursed Long Sword ('(')      It has 15 out of 15 hit
#   plain  after   The Partly Melted Uncursed ...     It has  5 out of 15 hit
#   magic  before  ... Long Sword, Holy Avenger +2    It has 38 out of 35 hit
#   magic  after   ... Long Sword, Holy Avenger +2    It has 38 out of 35 hit
#
# The Holy Avenger's 38 of 35 is not damage: item generation sets its plus
# after its hit points, so it arrives over its own maximum and the game calls
# it "Mildly Damaged" before a blow is struck. This check compares the FIGURES,
# which that quirk leaves alone, and separately requires that "Melted" -- the
# word acid damage writes -- never appears.
#
# BOTH HALVES, because either alone can pass by accident. The plain half alone
# would also pass on a build that bypassed EVERY item's hardness; the magical
# half alone would also pass on a build that bypassed none.
#
# THE GUARD. "The magical sword was not damaged" proves nothing if the
# retaliation never reached it. A blow that KILLS its blob leaves no item for
# the retaliation to aim at and the engine aims it at the striker instead,
# printing "Acid splashes you!". Each run therefore requires the other line,
# "Acid splashes the <weapon>", on at least one strike screen.
#
# TWO SESSIONS, not one. Every retaliation that lands on the character costs
# him 2d4 hit points and a level-one orc cannot pay for seven blows.
#
# PROVED RED on 2026-09-10 with the mutation below, which restores the old
# behaviour by never bypassing hardness. The inner run printed:
#
#   |   FAIL  0/1 screens carry: Melted Uncursed Long Sword
#   |         it should prove: three blows melt the plain sword
#   |   FAIL  1/1 screens still carry: It has 15 out of 15 hit
#   |         it should prove: the plain sword lost hit points
#   | FAIL: a plain weapon is damaged where a magical one is not
#   PROVED RED: with src/Fight.cpp mutated, this check exits 1.
#
# Usage: tools/check_dequ_magic_hardness.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Fight.cpp \
    'e2.ignoreHardness = (e2.saveDC <= 0 && !it->isMagic());' \
    'e2.ignoreHardness = false;'

echo "--- a plain long sword: hardness 10, bypassed ---"
check_run tools/keys/dequ-hardness-plain.keys 5
check_screens '*-plain-strike-*'
check_expect "splashes the long sword" \
    "the blob answered a blow by attacking the sword itself"
check_screens '*-plain-before'
check_expect "The Uncursed Long Sword ('" \
    "the character wields an ordinary long sword"
check_expect "It has 15 out of 15 hit" \
    "and it is undamaged before the first blow"
check_screens '*-plain-after'
check_expect "Melted Uncursed Long Sword" \
    "three blows melt the plain sword"
check_reject "It has 15 out of 15 hit" \
    "the plain sword lost hit points"

echo
echo "--- a magical long sword: hardness kept ---"
check_run tools/keys/dequ-hardness-magic.keys 5
check_screens '*-magic-strike-*'
check_expect "splashes the Long Sword, Holy Avenger" \
    "the blob answered a blow by attacking the magical sword itself"
check_screens '*-magic-before'
check_expect "It has 38 out of 35 hit" \
    "the magical sword's hit points before the first blow"
check_screens '*-magic-after'
check_expect "It has 38 out of 35 hit" \
    "and the same figures after four blows: the acid never reached it"
check_reject "Melted" \
    "no acid damage is written on the magical sword"

check_done "a plain weapon is damaged where a magical one is not"
