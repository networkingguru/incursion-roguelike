#!/bin/bash
# Does the School Focus menu still hide a school the character already has?
# (bd inc-q1ei)
#
# THE RULE. School Focus is FF_MULTIPLE (src/FeatTab.cpp): it is meant to be
# taken more than once, in DIFFERENT schools. A second pick of the same school
# is worth nothing, because the reader in getSpellDC (src/Magic.cpp) assigns
# +2 rather than adding it -- so the feat slot is simply lost.
#
# THE DEFECT. The feat files its school in the stati's Mag:
#
#     GainPermStati(SCHOOL_FOCUS,NULL,SS_MISC,0,i,0);
#
# so Val is 0 and eID is 0. The nine guards that build the menu asked
#
#     if (!HasEffStati(SCHOOL_FOCUS,SC_ABJ))
#
# and HasEffStati's second argument is a RESOURCE ID, matched against eID.
# Every one of the nine was false forever, and the menu offered a school the
# character already held.
#
# THE ORACLE is the focus menu itself, twice in one generation. The orc mage
# takes School Focus, chooses Illusion, then takes School Focus again: the
# first menu carries Illusion and the second must not. The character sheet's
# feat page is read afterwards, where the two schools are listed one under the
# other -- that is what says the second pick was kept as a DIFFERENT school
# rather than thrown away.
#
# THE SECOND RUN guards the other half of the same condition. The Necromancy
# line carries a rule of its own, that an elf may not focus on Necromancy at
# all, and the orc cannot show it because his menu carries Necromancy on
# purpose. The elf's menu must be short of it and must still carry the rest.
#
# PROVED RED on 2026-09-11 by putting HasEffStati back in the Illusion guard.
# The inner run printed:
#
#   |   FAIL  1/1 screens still carry: Illusion
#   |         it should prove: the school he just took is not offered again
#   |         first: Illusion
#   | FAIL: a school already focused on is gone from the second menu, and the elf ban still holds
#   PROVED RED: with src/Create.cpp mutated, this check exits 1.
#
# The second mutation, which drops the elf ban, was proved red the same day by
# moving it above the first: "FAIL 1/1 screens still carry: Necromancy". Only
# the FIRST mutation a check declares is performed by --prove-red.
#
# Usage: tools/check_school_focus_menu.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Create.cpp \
'            if (!(focused & SC_ILL))' \
'            if (!HasEffStati(SCHOOL_FOCUS,SC_ILL))'

check_mutation src/Create.cpp \
'            if (!((focused & SC_NEC) || isMType(MA_ELF)))' \
'            if (!(focused & SC_NEC))'

check_run tools/keys/school-focus.keys 42

check_screens '*-school-menu-1'
check_expect "Choose a focus school:" \
    "the first School Focus reached its school menu"
check_expect "Illusion" \
    "and Illusion is on offer, because he holds no focus yet"

check_screens '*-school-menu-2'
check_expect "Choose a focus school:" \
    "the second School Focus reached its school menu too"
check_expect "Abjuration" \
    "and the menu is drawn, so an absent school means absent"
check_reject "Illusion" \
    "the school he just took is not offered again"

check_screens '*-sheet'
check_expect "School Focus:" \
    "the character sheet lists the feat"
check_expect "Evocation" \
    "and the second pick was kept, in a school of its own"

check_run tools/keys/school-focus-elf.keys 42

check_screens '*-elf-school-menu'
check_expect "Choose a focus school:" \
    "the elf reached the same menu"
check_expect "Illusion" \
    "and it is drawn, so an absent school means absent"
check_reject "Necromancy" \
    "an elf is still refused Necromancy"

check_done "a school already focused on is gone from the second menu, and the elf ban still holds"
