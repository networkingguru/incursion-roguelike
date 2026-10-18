#!/bin/bash
# gate: live
# inc-5p2z: is a divine spell picked into a FREE slot at level-up held at once?
#
# THE DEFECT. Player::LearnSpell (src/Create.cpp) treats every arcane, divine
# and primal row as a "re-pick at rest" row. Outside creation a mark only sets
# a pending bit (SP_PEND_DIV / SP_PEND_PRI), and Player::ApplySpellSelection
# makes it held at the next full rest. The game says "Your selection takes
# effect at your next full rest." A new level's free slot therefore stays empty
# until the player rests.
#
# REQUIRED. A divine or primal mark into a FREE slot (fewer held spells than
# slots at that spell level) is held and castable at once. A swap (unmark held
# A, mark B, no free slot) still waits for rest. Arcane is unchanged.
# This check covers the free-slot case only; the swap case is covered by
# tools/check_rest_per_source.sh case b.
#
# THE ORACLE is the cast menu (the Spell Manager opened with 'm'): it lists only
# HELD spells. Tracing: the fixture Henk (orc-priest-seed4-gate.sav) is Priest 1;
# the key script gains Priest 2, whose Learn Spells screen reads "Level 1 - 4 of
# 5 slots". It marks Detect Evil, confirms, and opens the cast menu without a
# rest. Preconditions are asserted, so a drifted run exits 2, never 1:
#   - the Learn screen showed Detect Evil marked ("[*] (div)Detect Evil")
#   - the cast menu opened and lists Bane (an already-held spell)
# Then the verdict: the cast menu must list "(div)Detect Evil".
#
# Usage: tools/check_newlevel_divine_spell.sh
#   0 the new pick is castable at once   1 it is not   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/orc-priest-seed4-gate.sav
[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE."

export INCURSION_LOAD="$FIXTURE"
check_run tools/keys/newlevel-divine-mark.keys 4

check_screens '*-before-mark'
check_expect "Level 1 - 4 of 5 slots" "precondition: the new level has a free level-1 slot" ||
    _check_die 2 "precondition failed: no free slot, so the case is not what it claims."
check_screens '*-marked'
check_expect "[*] (div)Detect Evil" "precondition: Detect Evil is marked" ||
    _check_die 2 "precondition failed: the mark was not made."
check_screens '*-castmenu'
check_expect "(div)Bane" "precondition: the cast menu opened and lists a held spell" ||
    _check_die 2 "precondition failed: the cast menu did not open."
check_expect "(div)Detect Evil" "the new pick is castable with no rest"
check_done "a divine spell picked into a free slot at level-up is castable without a rest"
