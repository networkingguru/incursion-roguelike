#!/bin/bash
# gate: live
# Growth into a bulk with no room must keep the old size, not delete the
# creature; a shape change must recalculate size at once. (bd inc-o37m, inc-7giv)
#
# fact: character -- fixture orc-mage-seed4-gate (only a live player and map are needed)
# fact: the map -- the probe walls in a box it finds free of creatures and features, and logs INCONCLUSIVE (exit 2) when none exists
# fact: the creatures -- the probe builds an ogre and a dwarf; no spawn roll, no AI turn runs
# fact: Enlarge -- the probe gains the ADJUST A_SIZ +1 status directly; no cast, no save
# fact: text -- the check reads the probe's own numbers, not game messages
#
# THE DEFECT. Creature::CalcValues grew a creature into a bulk (Huge) and called
# Thing::PlaceNear, which deleted the creature when no square fit; the caller
# then read a NULL map. A shape change also left Attr[A_SIZ] stale until a later
# recalculation (Creature::Shapeshift never recalculated).
# THE FIX. CalcValues caps the size at the old one when a dry-run PlaceNear finds
# no room, and prints once; Shapeshift calls CalcValues.
#
# THE ORACLE is src/GrowNoRoomProbe.cpp (INCURSION_GROW_NOROOM_PROBE):
#   a  ogre (Large) in a 1-wide corridor gains Enlarge: alive, size 5, no bulk,
#      exactly 1 message across three recalculations
#   b  walls removed, one recalculation: alive, size 6, bulk field present, 0 messages
#   c  dwarf with Enlarge polymorphs into a phase spider: size 6 at once
# --prove-red reverts the cap, so scene a deletes the ogre. Revert the
# CalcValues() call in Shapeshift by hand to see scene c fail.
#
# Usage: tools/check_grow_noroom.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Values.cpp \
'            if (!PlaceNearSearch(x,y,true,(int8)Attr[A_SIZ])) {' \
'            if (0 && !PlaceNearSearch(x,y,true,(int8)Attr[A_SIZ])) {'

export INCURSION_GROW_NOROOM_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav

check_run tools/keys/load-char-sheet.keys 1

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 "the run logged nothing; the probe never ran."
if grep -q 'GROW_NOROOM_PROBE INCONCLUSIVE' "$LOG"; then
    grep -m1 'GROW_NOROOM_PROBE INCONCLUSIVE' "$LOG"
    _check_die 2 "the probe could not set up; see the line above."
fi
grep -q 'GROW_NOROOM_PROBE FIRE' "$LOG" || _check_die 2 \
    "no FIRE line: is GrowNoRoomProbe still called from Game::Play?"
echo "specimen: $LOG"
grep 'GROW_NOROOM_PROBE [abc] ' "$LOG"

fail=0
grep -q 'GROW_NOROOM_PROBE a alive=1 size=5 bulk=0 msgs=1$' "$LOG" || { echo "FAIL scene a"; fail=1; }
grep -q 'GROW_NOROOM_PROBE b alive=1 size=6 bulk=1 msgs=0$' "$LOG" || { echo "FAIL scene b"; fail=1; }
grep -q 'GROW_NOROOM_PROBE c alive=1 before=5 after=6$' "$LOG" || { echo "FAIL scene c"; fail=1; }
grep -q 'GROW_NOROOM_PROBE COMPLETE' "$LOG" || { echo "FAIL probe did not complete"; fail=1; }
[ "$fail" = 0 ] || exit 1
echo "PASS: no-room growth keeps the old size and retries; a shape change recalculates"
exit 0
