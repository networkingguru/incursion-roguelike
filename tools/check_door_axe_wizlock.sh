#!/bin/bash
# gate: live
# Do axes hurt a door fully, and does a wizard lock stop doubling hardness? (bd inc-h22n)
#
# WHAT RUNS. The same probe session as tools/check_door_pick_kick.sh. The probe
# hands Door::Event an EV_DAMAGE of a fixed 30 points (slashing for a battleaxe
# and a long sword, blunt for a light mace) on an oak door given 1000 HP, and
# reads how many HP the door lost. Oak is wood: hardness 5. The weapon items are
# real resources, so a test on WG_AXES or WT_BLUNT sees the real flags.
#
# WHAT IT ASSERTS (design point 4):
#   axe            loses 30 - 5 = 25   (full damage; today 30/3 - 5 = 5)
#   long sword     loses 30/3 - 5 = 5  (other non-blunt: one third; unchanged)
#   light mace     loses 25            (blunt: full; unchanged)
#   mace, wizlock  loses 25            (hardness not doubled; today 30 - 10 = 20)
#   axe,  wizlock  loses 25            (today 30/3 - 10 = 0)
#
# LIMIT. The player's damage line "x2 (wizlock)" is drawn in a window the probe
# does not read, so removal of that display text is not asserted.
#
# Usage: tools/check_door_axe_wizlock.sh [--selftest]   exit 0 pass, 1 fail, 2 inconclusive
case "${1:-}" in
    --selftest) exec python3 "$(dirname "$0")/check_door_probe.py" selftest ;;
esac
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_DOORPICK_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav

check_run tools/keys/door-pick-kick.keys 1 > /dev/null || exit $?
LOG="$CHECK_RUN/logs/doorpick.log"
[ -f "$LOG" ] || _check_die 2 \
    "the run wrote no $LOG, so the probe never ran." \
    "Is DoorPickProbe still called from Game::Play (src/Main.cpp)?"
python3 tools/check_door_probe.py axe "$LOG"
RC=$?
echo
case "$RC" in
    0) echo "PASS: axes deal full damage and a wizard lock does not double hardness" ;;
    1) echo "FAIL: weapon damage to a door departs from the settled design (inc-h22n point 4)" ;;
    *) echo "INCONCLUSIVE: the probe could not measure everything; read the lines above" ;;
esac
exit "$RC"
