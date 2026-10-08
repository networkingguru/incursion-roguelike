#!/bin/bash
# gate: live
# Does a Chaotic character whose desired alignment is Neutral stop being
# Chaotic through ordinary play -- the game printing "You are now ..." and
# the character sheet's Align line changing? (bd inc-r6ae)
#
# This is the leaving-Chaotic half of inc-r6ae's game-play evidence.
# tools/check_align_lawchaos.sh already proves the same property by driving
# the engine directly through INCURSION_ALIGN_PROBE (Traced); this check
# reads the answer off the screen after ordinary player commands (Observed).
#
# THE DEFECT. src/Prayer.cpp's committed-Chaotic branch pinned the law/chaos
# score (alignLC) with `alignLC = max(30, alignLC);` where its committed-evil
# twin (the AL_EVIL branch, read one block above) already used
# `alignGE = min(30, alignGE);`. A non-chaotic act decays alignLC toward zero
# (`alignLC = (alignLC * (10 - vMag)) / 10;`), but the very next line's
# max(30,...) pinned it straight back to 30 -- above the 20 threshold -- so a
# Chaotic character could never leave Chaotic, however many non-chaotic acts
# it committed.
#
# THE ROUTE, tools/keys/align-leave-chaotic-play.keys. tools/keys/chargen.keys'
# standard orc barbarian, but Chaotic Neutral is chosen at generation instead
# of Neutral; generation sets alignLC to +50 for a Chaotic character
# (src/Create.cpp:472-473). He carries no Diplomacy and Intimidate +6, so
# Creature::Request (src/Social.cpp) offers "Use Intimidate?" and fires the
# COERCION aligned act (AL_NONCHAOTIC|AL_LAWFUL, magnitude 3); the
# AL_NONCHAOTIC half is what decays alignLC here. The desired alignment is
# stated with the character sheet's own '[D] Alignment' command and set to
# Neutral: AlignedAct clamps alignLC only while the character does NOT desire
# Chaotic (the `if (!(dAlign & AL_CHAOTIC))` guard), so without this the score
# would not move at all. A wizard-summoned, frozen human, one square east, is
# the victim; each coercion aborts at the "Direct Creature Where" prompt, so
# no TRIED flag is set and the same victim serves again.
#
# THE COUNT, from AlignedAct's own arithmetic: alignLC starts at 50.
#   1st: 50 * 7/10 = 35 (int truncation) -> clamp -> 30
#   2nd: 30 * 7/10 = 21               -> clamp -> 21 (below the clamp's own 30)
#   3rd: 21 * 7/10 = 14               -> clamp -> 14, which is below the |20|
#        threshold: AL_CHAOTIC is cleared on the THIRD coercion.
# Four coercions are sent for margin; the fourth moves no flag and prints
# nothing, which is itself correct (already True Neutral).
#
# WHAT IS ASSERTED, all from screen dumps:
#   - "You feel guilty (coercion)." -- the coercions fired the non-chaotic
#     act, so the run reached the state where the flag could clear. This is
#     the positive control; without it a session that coerced nothing would
#     still satisfy the absence-based half.
#   - "You are now True Neutral." -- the alignment change line AlignedAct
#     prints (src/Prayer.cpp), which is the fix.
#   - "Align  Neutral" -- the character sheet's own Align line, read after the
#     coercions, so the change is not merely a message.
# A run that cannot find its screens is INCONCLUSIVE (check_lib.sh), never a
# pass. Red on the un-fixed code: the last two strings never appear, and the
# character sheet stays "Align  Chaotic Neutral" however many acts are sent.
#
# Usage: tools/check_align_leave_chaotic_play.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The mutation this check defends, read straight off the fix: the clamp that
# pins a committed-Chaotic character's score.
check_mutation src/Prayer.cpp \
'      if (!(dAlign & AL_CHAOTIC))
        alignLC = min(30, alignLC);
      }' \
'      if (!(dAlign & AL_CHAOTIC))
        alignLC = max(30, alignLC);
      }'

INCURSION_RUN_DIR="$PWD/logs/align-leave-chaotic-play/seed-1-$$"
rm -rf "$INCURSION_RUN_DIR"
export INCURSION_RUN_DIR

check_run tools/keys/align-leave-chaotic-play.keys 1

check_screens '*'
check_expect "You feel guilty (coercion)." \
    "the coercions fired the non-chaotic act that decays the law/chaos score"
check_expect "You are now True Neutral." \
    "AlignedAct printed the alignment change the fix enables"
check_expect "Align  Neutral" \
    "the character sheet's Align line carries the new alignment"

check_done "a Chaotic character whose desired alignment is Neutral left" \
    "Chaotic through the ordinary Issue Request command: alignLC 50->30->21->14," \
    "the game printed \"You are now True Neutral.\", and the sheet agrees."
