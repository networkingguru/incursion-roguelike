#!/bin/bash
# gate: live
# Does a Neutral character who has STATED a Chaotic desired alignment become
# Chaotic Neutral through ordinary play -- the game printing "You are now
# Chaotic Neutral." and the character sheet's Align line changing? (bd inc-r6ae)
#
# This is the treachery half of inc-r6ae's game-play evidence.
# tools/check_align_coercion_play.sh already showed the Lawful side (the
# missing else branches); this check shows the Chaotic side, which carries a
# second, independent defect: a Neutral character's Chaotic act moved the
# law/chaos score (alignLC) the WRONG WAY (-=, toward Lawful, where its
# evil/good twin already used +=). tools/check_align_lawchaos.sh proves the
# same property by driving the engine directly through INCURSION_ALIGN_PROBE,
# so its evidence is Traced; this check reads the answer off the screen after
# ordinary player commands, which is Observed.
#
# THE DEFECT. src/Prayer.cpp's Neutral-character AL_CHAOTIC branch used
# `alignLC -= (int16)e.vMag;` where its good/evil twin (the AL_EVIL branch,
# read one block above) already used `+=`. A Chaotic act on a Neutral
# character moved the score toward Lawful instead of Chaotic, so it could
# never reach the +20 threshold and the character could never become Chaotic
# no matter how many Chaotic acts it committed.
#
# THE ROUTE, tools/keys/align-treachery-play.keys. An elf rogue spends every
# skill rank on skills other than Bluff's rivals, so Bluff +7 outranks both
# Intimidate +5 and Diplomacy +5 (an orc cannot be used here: the orc race
# grants Intimidate racially, so an orc's Intimidate always outscores its
# Diplomacy and Creature::Request never offers Bluff). With Intimidate not
# greater than Diplomacy and Bluff greater, Creature::Request (src/Social.cpp)
# offers "Use Bluff?" and fires the TREACHERY aligned act
# (AL_NONLAWFUL|AL_CHAOTIC, magnitude 3, src/Social.cpp:1184-1192). The
# desired alignment is stated with the character sheet's own '[D] Alignment'
# command; without it AlignedAct clamps the score back to zero as a designed
# guard. A wizard-summoned, frozen human, one square east, is the victim.
# Each treachery aborts at the "Direct Creature Where" prompt, so no TRIED
# flag is set and the same victim serves again. Seven treacheries drive
# alignLC from 0 to 21, past the +20 threshold; an eighth is sent for margin.
#
# WHAT IS ASSERTED, all from screen dumps:
#   - "You feel closer to chaotic independence." -- the treacheries moved the
#     score, so the run reached the state where the flag could be set. This is
#     the positive control; without it a session that tried nothing would
#     still satisfy the absence-based half.
#   - "You are now Chaotic Neutral." -- the alignment change line AlignedAct
#     prints (src/Prayer.cpp), which is the fix.
#   - "Align  Chaotic Neutral" -- the character sheet's own Align line, read
#     after the treacheries, so the change is not merely a message.
# A run that cannot find its screens is INCONCLUSIVE (check_lib.sh), never a
# pass. Red on the un-fixed code: the last two strings never appear, and the
# character sheet stays "Align  Neutral".
#
# Usage: tools/check_align_treachery_play.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The mutation this check defends, read straight off the fix: the sign a
# Neutral character's Chaotic act moves alignLC by. Reverting only this one
# line (not the else-branch that sets AL_CHAOTIC, which
# check_align_coercion_play.sh already mutates) is enough on its own to keep
# this route from ever reaching Chaotic.
check_mutation src/Prayer.cpp \
'    else if (e.EParam & AL_CHAOTIC) {
      alignLC += (int16)e.vMag;
      if (!(dAlign & AL_CHAOTIC))
        alignLC = min(alignLC,0);
      }' \
'    else if (e.EParam & AL_CHAOTIC) {
      alignLC -= (int16)e.vMag;
      if (!(dAlign & AL_CHAOTIC))
        alignLC = min(alignLC,0);
      }'

INCURSION_RUN_DIR="$PWD/logs/align-treachery-play/seed-1-$$"
rm -rf "$INCURSION_RUN_DIR"
export INCURSION_RUN_DIR

check_run tools/keys/align-treachery-play.keys 1

check_screens '*'
check_expect "You feel closer to chaotic independence." \
    "the seven treacheries moved the law/chaos score toward Chaotic"
check_expect "You are now Chaotic Neutral." \
    "AlignedAct printed the alignment change the fix enables"
check_expect "Align  Chaotic Neutral" \
    "the character sheet's Align line carries the new alignment"

check_done "a Neutral character who stated a Chaotic desired alignment became" \
    "Chaotic Neutral through the ordinary Issue Request command: alignLC 21," \
    "the game printed \"You are now Chaotic Neutral.\", and the sheet agrees."
