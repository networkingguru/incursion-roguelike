#!/bin/bash
# Does School Focus (Illusion) still raise the disbelief DC? (bd inc-q1ei)
#
# THE RULE. School Focus adds 2 to the save DC of the focused school's spells.
# For illusions that save is the disbelief roll in src/Magic.cpp, which is
# computed on the spot and not through getSpellDC.
#
# THE DEFECT. The feat files its school in the stati's Mag:
#
#     GainPermStati(SCHOOL_FOCUS,NULL,SS_MISC,0,i,0);
#
# so Val is 0. The disbelief save asked
#
#     (e.EActor->HasStati(SCHOOL_FOCUS,SC_ILL) ? 2 : 0)
#
# and HasStati's second argument is matched against Val (inc/Inline.h), which
# is 0 and never SC_ILL. The bonus reached no disbelief save ever.
#
# THE ORACLE is the printed save line, which is the only place a player can
# read that DC. src/Creature.cpp writes "<Name>'s Will Save: 1d20 (n) = n vs
# DC d [success|failure]." to the numbers window whenever the player perceives
# the roller, and the pinned settings store rolls, so the line is in the 'v'
# message history as well. The d20 varies with the seed; the DC does not.
#
# Measured on seed 42 under tools/fixtures/options-2026-08-22.dat, one orc
# mage with School Focus (Illusion) casting Phantasmal Force at a goblin:
#
#   before   Goblin's Will Save: 1d20 (6) = 6 vs DC 11 [failure].
#   after    Goblin's Will Save: 1d20 (6) = 6 vs DC 13 [failure].
#
# 11 is 10 + SkillLevel(SK_ILLUSION)/2, with the feat contributing nothing.
#
# WHAT THIS CHECK DOES NOT COVER. The third reader of the same stati, the
# spell DC in getSpellDC (src/Magic.cpp), already masked Mag correctly and was
# not touched. tools/check_school_focus_menu.sh covers the generation menu.
#
# PROVED RED on 2026-09-11 by putting the HasStati test back. The inner run
# printed:
#
#   |   FAIL  0/1 screens carry: vs DC 13
#   |         it should prove: School Focus (Illusion) added its 2 to the DC
#   |   FAIL  1/1 screens still carry: vs DC 11
#   |         it should prove: the unfocused DC is gone
#   |         first: vs DC 11
#   | FAIL: an illusionist's School Focus still moves the disbelief DC
#   PROVED RED: with src/Magic.cpp mutated, this check exits 1.
#
# Usage: tools/check_school_focus_dc.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Magic.cpp \
'        ill_focus = 0;
        StatiIterNature(e.EActor,SCHOOL_FOCUS)
            if (S->Mag & SC_ILL)
              ill_focus = 2;
        StatiIterEnd(e.EActor)' \
'        ill_focus = e.EActor->HasStati(SCHOOL_FOCUS,SC_ILL) ? 2 : 0;'

check_run tools/keys/school-focus.keys 42

check_screens '*-disbelief'
check_expect "Goblin's Will Save:" \
    "the illusion reached the goblin and it rolled to disbelieve"
check_expect "vs DC 13" \
    "School Focus (Illusion) added its 2 to the DC"
check_reject "vs DC 11" \
    "the unfocused DC is gone"

check_done "an illusionist's School Focus still moves the disbelief DC"
