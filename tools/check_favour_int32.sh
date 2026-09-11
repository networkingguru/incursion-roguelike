#!/bin/bash
# gate: live
# Can a character's favour now pass 32767 without wrapping negative? (bd inc-upw.31)
#
# THE DEFECT. EventInfo::EParam is an int32 (inc/Events.h:227), but the SCRIPT
# view of it was declared int16 (inc/Api.h:723). The resource compiler writes
# the dispatcher from that declaration, so lib/dispatch.h:3551 truncated every
# write a script made to the field:
#
#     pe->EParam = (int16)val;      /* was */
#     pe->EParam = val;             /* is  */
#
# Character::calcFavour (src/Prayer.cpp:648-670) is lossless in C++ -- int32
# throughout -- but it round-trips the running total through the script:
#
#     e.EParam = Favour;  ReThrow(EV_CALC_FAVOUR,e);  Favour = e.EParam;
#
# and all eight gods that handle EV_CALC_FAVOUR write the field back
# (lib/religion.irh:676, 1054, 1723, 2170, 2529, 3855, 4727, 5112). So every
# favour total over 32767 came back WRAPPED, not capped: 120000 became -11072.
# Character::gainFavour allows ten favour levels, and Hesani's FAVOUR_CHART
# (lib/religion.irh:1983) puts levels 7, 8 and 9 at 48000, 64000 and 92000.
# None of the three could ever be reached, and the abilities behind them were
# dead content.
#
# WHAT THE RUN DOES. tools/keys/favour-int32.keys makes the orc warrior of
# dequ-setup.keys on seed 5, opens the wizard menu, and takes "Become Divine
# Champion" for Hesani. That sets one sacrifice category to 30000 -- under
# 32767, which is why the defect hid for years -- and Hesani's own handler
# multiplies it to 120000 for a level-one non-barbarian. The character sheet
# prints the figure.
#
# THE TWO-PASS BUILD. inc/Api.h is compiled into nothing. The resource compiler
# READS it and GENERATES lib/dispatch.h (src/RComp.cpp:219, GenerateDispatch),
# and build_macos.sh:380 runs that regeneration AFTER the binary is linked. One
# build after the declaration changes therefore links the OLD dispatcher and
# merely writes the new one to disk; the SECOND build is the one that compiles
# it in. check_build is overridden below for that reason -- see the comment
# there for the measurement.
#
# PROVED RED on 2026-09-11 by putting the int16 declaration back:
#
#   |   FAIL  0/1 screens carry: (Favour 120000, Lev 9, Pen 0%)
#   |         it should prove: the sheet prints the whole 32-bit total, positive
#   |   FAIL  0/1 screens carry: You are the hand of Hesani
#   |         it should prove: favour level 9 -- 7, 8 and 9 all need over 32767
#   |   FAIL  1/1 screens still carry: Hesani is noncommital
#   |         it should prove: no favour level at all, which is what a wrapped total gives
#   |         first: Hesani is noncommital
#   | FAIL: favour over 32767 survives the trip through script
#   PROVED RED: with inc/Api.h mutated, this check exits 1.
#
# The broken run printed "(Favour -11072, Lev 0, Pen 0%)", which is 120000
# truncated to sixteen bits.
#
# Usage: tools/check_favour_int32.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# TWO BUILDS PER PASS, because the fix site is a declaration the build reads
# rather than code the build compiles. Measured on 2026-09-11 with the
# mutation in place: after one build the sheet still read "(Favour 120000,
# Lev 9, Pen 0%)", and only after the second did it read "(Favour -11072,
# Lev 0, Pen 0%)". Without this, --prove-red would rebuild once, measure a
# binary that still held the fix, and report that the check passed with the fix
# broken. Clearing CHECK_BUILT is what defeats check_build's own once-per-run
# cache.
eval "$(declare -f check_build | sed '1s/^check_build/check_build_pass/')"
check_build() { # <posix|sdl>
    CHECK_BUILT=""; check_build_pass "$1"
    CHECK_BUILT=""; check_build_pass "$1"
}

check_mutation inc/Api.h \
'system int32   T_EVENTINFO::EParam;' \
'system int16   T_EVENTINFO::EParam;'

check_run tools/keys/favour-int32.keys 5

check_screens '*-favour'
check_expect "(Favour 120000, Lev 9, Pen 0%)" \
    "the sheet prints the whole 32-bit total, positive"
check_expect "You are the hand of Hesani" \
    "favour level 9 -- 7, 8 and 9 all need over 32767"
check_reject "Hesani is noncommital" \
    "no favour level at all, which is what a wrapped total gives"

check_done "favour over 32767 survives the trip through script"
