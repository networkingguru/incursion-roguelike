#!/bin/bash
# gate: live
# Does praying for aid still work above 32767 favour? (bd inc-pf0p)
#
# THE DEFECT. Character::Pray (src/Prayer.cpp:1037) took the favour total into
# an int16 local, with an explicit cast off calcFavour(), which returns int32:
#
#     int16 retry, i, j, k, cFavour;        /* was */
#     cFavour = (int16)calcFavour(e.eID);   /* was */
#     int16 retry, i, j, k;                 /* is  */
#     int32 cFavour;                        /* is  */
#
# Every row of the god's AID_CHART is gated on that value at :1126. Past 32767
# the cast wrapped NEGATIVE -- 120000 becomes -11072 -- so every threshold
# comparison read `threshold > -11072`, took the `continue`, and the follower
# received NO AID AT ALL. 69 FAVOUR_CHART rows in lib/religion.irh exceed
# 32767, largest 500000, so this reached the top of nearly every god's ladder.
#
# WHY THIS IS A SECOND CHECK AND NOT AN EXTENSION OF check_favour_int32.sh.
# That one guards inc-upw.31, a different narrowing: the SCRIPT view of
# EventInfo::EParam in inc/Api.h, which truncated script write-backs through
# EV_CALC_FAVOUR. Its run reaches 120000 favour -- well past this wrap -- and
# still cannot see this defect, because it never prays. Its oracle is the
# character sheet's favour line, which reads through int32 and stays correct
# with this bug in place. Reverting this fix leaves all three of its
# assertions green. The two checks share a character and nothing else.
#
# THE CONTROL MATTERS HERE. MSG_PRAYER, "You are surrounded in a column of
# shimmering light.", prints at src/Prayer.cpp:1083 BEFORE the aid loop and is
# unconditional, so it must survive the mutation. If it ever goes missing the
# mutated run failed to pray at all and the two aid assertions below would be
# red for the wrong reason.
#
# ONE BUILD PER PASS, unlike check_favour_int32.sh. That check overrides
# check_build to build twice, because its fix site is a declaration the
# resource compiler READS to generate lib/dispatch.h, so the first build links
# the old dispatcher. This fix is a plain source line the compiler compiles
# directly, so the default single build measures it.
#
# Usage: tools/check_pray_aid_int32.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Prayer.cpp \
'    int32 cFavour;' \
'    int16 cFavour;'

check_run tools/keys/pray-aid-int32.keys 5

check_screens '*-prayed'
# FRAGMENTS, NOT WHOLE SENTENCES. The three messages land on one wrapped
# message line, and check_expect matches within a line: the full
# "You no longer feel fatigued." is split as "You no" / "longer feel
# fatigued." and never appears whole on either. Each string below is the
# longest run that stays inside one line at this seed and these options.
check_expect "longer feel fatigued" \
    "AID_REFRESH, Hesani's threshold 100 against 120000 favour"
check_expect "magical energy is replenished" \
    "AID_MANA, Hesani's threshold 0 against 120000 favour"
check_expect "column of shimmering light" \
    "the control: MSG_PRAYER is unconditional, so the prayer did happen"

check_done "favour over 32767 still buys the aid the AID_CHART grants"
