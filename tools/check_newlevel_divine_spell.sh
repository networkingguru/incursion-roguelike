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
# HELD spells, by bare name with a Src column. Tracing: the fixture Henk
# (orc-priest-seed4-gate.sav) is Priest 1; the key script gains Priest 2, whose
# Learn Spells table reads "Learn Spells: Level 1 (4 of 5 slots used)". It marks
# Detect Evil, Enter opens the summary box, Enter confirms, and the cast menu
# opens without a rest. Preconditions are asserted, so a drifted run exits 2:
#   - the table showed 4 of 5 slots used, then Detect Evil marked ("[*]")
#   - the summary box named the Detect Evil learn
#   - the cast menu opened and lists Bane (an already-held spell)
# Then the verdict: the cast menu must list "Detect Evil".
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
check_expect "Learn Spells: Level 1 (4 of 5 slots used)" "precondition: the new level has a free level-1 slot" ||
    _check_die 2 "precondition failed: no free slot, so the case is not what it claims."
check_screens '*-marked'
check_expect "[*]  Detect Evil" "precondition: Detect Evil is marked" ||
    _check_die 2 "precondition failed: the mark was not made."
check_screens '*-summary'
check_expect "Detect Evil" "precondition: the summary box names Detect Evil" ||
    _check_die 2 "precondition failed: the summary box did not open on the pick."
check_screens '*-castmenu'
check_expect "Bane" "precondition: the cast menu opened and lists a held spell" ||
    _check_die 2 "precondition failed: the cast menu did not open."
check_expect "Detect Evil" "the new pick is castable with no rest"
check_done "a divine spell picked into a free slot at level-up is castable without a rest"
