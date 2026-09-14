#!/bin/bash
# gate: live
# Does a reflected gaze name the monster that gazed? (bd inc-upw.30)
#
# WHAT WENT WRONG. src/Magic.cpp:944 answers a gaze effect aimed at a creature
# carrying GAZE_REFLECTION / GR_REFLECT by turning the effect around and telling
# every onlooker about it. The string used two bare <Obj> tokens and the call
# supplied one object. __XPrint (src/Message.cpp:471-480) reads a tag whose
# lowercased form is exactly "obj", "mon" or "itm" as "take the NEXT argument",
# so the first token consumed the only argument and the second read past the end
# of the vararg list, then handed the result to Thing::Name().
#
# This is the same shape as the A_DEQU save line of 2026-08-15, which looked
# right in source and printed "the orcish bastard sword +1 protects its orcish
# bastard sword +1" on screen. tools/check_xprint_tokens.sh counts tokens in
# source text and is blind to what reaches the player, which is why this check
# plays the game instead.
#
# THE ORACLE is the literal sentence on the screen, read after a bodak has
# gazed at a character who carries the stati.
#
# WHY A BODAK, and how it separates the two reflection sites. Two places answer
# a reflected gaze. src/Fight.cpp:1900 handles the A_GAZE row of a monster's
# attack table and prints "The <EActor>'s gaze is reflected!"; src/Magic.cpp:944
# handles an EF_GAZE magical effect and prints the sentence this check reads. A
# bodak has no A_GAZE row -- its attacks are A_SLAM and A_SEEM -- so the
# Fight.cpp branch cannot run for it, and its one spell is an EF_GAZE effect.
# The wording separates them a second time: only the Magic.cpp line says "back
# at", and the assertions below reject the Fight.cpp line by name.
#
# WHAT THE FIXED BUILD PRINTS, copied from the screen:
#
#     The bodak's gaze is reflected back at it!
#
# PROVED RED on 2026-09-11 by putting the unnumbered tags back:
#
#     "The <Obj>'s gaze is reflected back at <him:Obj>!"
#
# The mutated build printed no sentence at all. It died where it formatted one,
# and logged this first:
#
#     Probable parameter mismatch in __XPrint; msg = "The <Obj>'s gaze is
#     reflected back at <him:Obj>!", POV=31017435136, Subject=0
#
# with a call stack of Monster::ChooseAction -> ThrowEff -> Creature::Invoke ->
# Magic::MagicEvent -> Magic::ABallBeamBolt -> Magic::MagicStrike ->
# Thing::IDPrint -> Player::__IPrint -> __XPrint -> Error, and then the process
# took SIGBUS (tools/headless.sh reported "ended: exit 138"). That is the first
# observation of this defect biting in play rather than in a source scan.
#
# WHY THIS CHECK CAN BE PROVED RED AT ALL. Here the death IS the measurement,
# and tools/check_lib.sh's check_run used to report every abnormal ending as
# INCONCLUSIVE, which --prove-red reads as "nothing is proved". This check
# answered that with a check_run of its own for a day. The rule is shared now:
# check_run FAILS a session the game killed -- a Fatal(), a watchdog stop, or a
# signal -- and keeps INCONCLUSIVE for the endings that say the key script or
# the harness drifted. Read the fourth rule in the header of tools/check_lib.sh.
# This file overrides nothing.
#
# Usage: tools/check_gaze_reflect_message.sh              (0 pass, 1 fail, 2 no measurement)
#        tools/check_gaze_reflect_message.sh --prove-red
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Magic.cpp \
    "The <Obj1>'s gaze is reflected back at <him:Obj1>!" \
    "The <Obj>'s gaze is reflected back at <him:Obj>!"

check_run tools/keys/gaze-reflect-message.keys 4

# The stati is on the character before any gaze arrives. src/Sheet.cpp:653
# writes this row of the sheet's Specials column.
check_screens '*-sheet-specials'
check_expect "Gaze Reflection" "the caster carries the stati before any gaze arrives"

check_screens '*-wait*'
check_expect "eyes glow with a black aura" \
    "the bodak really cast its gaze, so a reflection had something to answer"
check_expect "The bodak's gaze is reflected back at it!" \
    "the sentence names the gazing monster once, then pronouns it"
check_reject "<Obj" \
    "no raw format tag reached the screen"
check_reject "gaze is reflected back at the bodak" \
    "the monster is named once, not twice"
check_reject "The bodak's gaze is reflected!" \
    "the line came from src/Magic.cpp, not from src/Fight.cpp's A_GAZE branch"

check_done "a reflected gaze names the gazer once, in a sentence that parses"
