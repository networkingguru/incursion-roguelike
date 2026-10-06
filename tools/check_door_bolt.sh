#!/bin/bash
# gate: live
# A natural-attack breath through a closed door must not crash. (bd inc-a9m3)
#
# THE DEFECT. Magic::ABallBeamBolt adds a solid feature (a door) to its target
# list, then re-throws each target with ourEvent, which is EV_HIT for a
# natural attack. Creature::Event EV_HIT calls Creature::Hit, which reads
# e.EVictim as a Creature with no type check; a Door's vtable is shorter, so
# the InSlot(SL_ARMOUR) call (src/Fight.cpp) is a wild jump: SIGBUS.
#
# THE FIX. At Magic::ABallBeamBolt's hit loop the ReThrow now sends a
# non-creature target EV_MAGIC_STRIKE instead of EV_HIT, the event non-natural
# spells already send it.
#
# THE ORACLE is INCURSION_DOOR_BOLT_PROBE, which arms DoorBoltProbe
# (src/DoorBoltProbe.cpp), run once at the top of Game::Play. A water mephit
# breathes (A_BREA, via Creature::SAttack) at the player through a closed door
# between them. The probe logs "DOOR_BOLT_PROBE COMPLETE" only if the breath
# returns. A signal exit (check_lib reads 128+ as FAIL), or a missing COMPLETE
# line, is the defect. A missing FIRE line is INCONCLUSIVE.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation below
# restores the original ReThrow line; the breath then throws EV_HIT at the door
# and the run dies with SIGBUS (exit 138).
#
# Usage: tools/check_door_bolt.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Magic.cpp \
'      ReThrow((e.isNAttack && !cr->isCreature()) ? EV_MAGIC_STRIKE : ourEvent, eCopy);' \
'      ReThrow(ourEvent, eCopy);'

export INCURSION_DOOR_BOLT_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav

check_run tools/keys/load-char-sheet.keys 1

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 "the run logged nothing; the probe never ran."
if grep -q 'DOOR_BOLT_PROBE INCONCLUSIVE' "$LOG"; then
    grep -m1 'DOOR_BOLT_PROBE INCONCLUSIVE' "$LOG"
    _check_die 2 "the probe could not set up; see the line above."
fi
grep -q 'DOOR_BOLT_PROBE FIRE' "$LOG" || _check_die 2 \
    "no FIRE line: is DoorBoltProbe still called from Game::Play?"
echo "specimen: $LOG"
if ! grep -q 'DOOR_BOLT_PROBE COMPLETE' "$LOG"; then
    echo "FAIL: the breath through a door never returned (inc-a9m3)"
    exit 1
fi
echo "PASS: a natural-attack breath through a closed door completed"
exit 0
