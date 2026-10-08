#!/bin/bash
# gate: live
# Does a Neutral character who has STATED a Lawful desired alignment become
# Lawful Neutral through ordinary play -- the game printing "You are now
# Lawful Neutral." and the character sheet's Align line changing? (bd inc-r6ae)
#
# This is the game-play half of inc-r6ae. tools/check_align_lawchaos.sh proves
# the law/chaos half of Character::AlignedAct mirrors its good/evil twin, but
# it drives the engine directly through INCURSION_ALIGN_PROBE, so its evidence
# is Traced, not Observed. This check asks for the same property through the
# commands a player uses, and reads the answer off the screen.
#
# THE DEFECT. src/Prayer.cpp moved a Neutral character's law/chaos score
# (alignLC) on a Lawful or Chaotic act, then cleared AL_LAWFUL / AL_CHAOTIC
# when the score did not pass the threshold -- but never SET either flag when it
# did, where the good/evil pair one block above sets AL_GOOD / AL_EVIL. So the
# score could reach its cap and the alignment and the "You are now ..." line
# never came.
#
# THE ROUTE, tools/keys/align-coercion-play.keys. chargen.keys' orc barbarian
# is Neutral and has Intimidate +6 but no Diplomacy, so Creature::Request
# (src/Social.cpp) offers "Use Intimidate?" and fires the coercion aligned act
# (AL_NONCHAOTIC|AL_LAWFUL, magnitude 3). The desired alignment is stated with
# the character sheet's own '[D] Alignment' command; without it a designed
# clamp holds the score at zero. A wizard-summoned, frozen human, one square
# east, is the non-evil victim. Each coercion aborts at the "Direct Creature
# Where" prompt, so no TRIED flag is set and the same victim serves again. Seven
# coercions drive alignLC from 0 to -21, past the |20| threshold.
#
# WHAT IS ASSERTED, all from screen dumps:
#   - "You feel closer to lawful stability." -- the coercions moved the score,
#     so the run reached the state where the flag could be set. This is the
#     positive control; without it a session that coerced nothing would still
#     satisfy the absence-based half.
#   - "You are now Lawful Neutral." -- the alignment change line AlignedAct
#     prints (src/Prayer.cpp), which is the fix.
#   - "Align  Lawful Neutral" -- the character sheet's own Align line, read
#     after the coercions, so the change is not merely a message.
# A run that cannot find its screens is INCONCLUSIVE (check_lib.sh), never a
# pass. Red on the un-fixed code: the two latter strings never appear.
#
# Usage: tools/check_align_coercion_play.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The mutation this check defends, read straight off the fix: the two else
# branches that set the flags. Removing them is the base-code defect.
check_mutation src/Prayer.cpp \
'    if (alignLC > -20)
      nAlign &= (~AL_LAWFUL);
    else
      nAlign |= AL_LAWFUL;
    if (alignLC < 20)
      nAlign &= (~AL_CHAOTIC);
    else
      nAlign |= AL_CHAOTIC;' \
'    if (alignLC > -20)
      nAlign &= (~AL_LAWFUL);
    if (alignLC < 20)
      nAlign &= (~AL_CHAOTIC);'

# A directory of its own, keyed to this process, under logs/ like every other
# specimen. headless.sh would pick a unique one anyway; naming it makes the
# check's own evidence obvious.
INCURSION_RUN_DIR="$PWD/logs/align-coercion-play/seed-1-$$"
rm -rf "$INCURSION_RUN_DIR"
export INCURSION_RUN_DIR

check_run tools/keys/align-coercion-play.keys 1

check_screens '*'
check_expect "You feel closer to lawful stability." \
    "the seven coercions moved the law/chaos score toward Lawful"
check_expect "You are now Lawful Neutral." \
    "AlignedAct printed the alignment change the fix enables"
check_expect "Align  Lawful Neutral" \
    "the character sheet's Align line carries the new alignment"

check_done "a Neutral character who stated a Lawful desired alignment became" \
    "Lawful Neutral through the ordinary Issue Request command: alignLC -21," \
    "the game printed \"You are now Lawful Neutral.\", and the sheet agrees."
