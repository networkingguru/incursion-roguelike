#!/bin/bash
# gate: live
# inc-47ws: does an animal companion walk over a trap that already sprung?
# Prints one COMPANION_TRAP line per mode; asserts only that the control works.
# fact: class, kit, animal-companion capacity -- druid-shoulder-metal-seed7-opt0822.sav
# fact: options (incl. Monsters Use Djikstra) -- tools/fixtures/options-2026-08-22.dat
# fact: map, no AI, wall with one gap holding the trap -- INCURSION_COMPANION_TRAP_PROBE scene
# fact: companion relationship -- probe calls MakeCompanion(player, PHD_ANIMAL) on a wolf
# fact: trap save (sprung = failed, avoided = made) -- INCURSION_FORCE_SAVE_ROLL=1 / 20
# fact: trap flags -- read from the trap after the real TriggerTrap, never written by the probe
# fact: player stays put -- tools/keys/companion-trap.keys sends only wait keys
. "$(dirname "$0")/check_lib.sh"
CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav
for mode in sprung avoided armed none; do
    export INCURSION_COMPANION_TRAP_PROBE="$mode" INCURSION_FORCE_SAVE_ROLL=1
    [ "$mode" = avoided ] && export INCURSION_FORCE_SAVE_ROLL=20
    check_run tools/keys/companion-trap.keys "${COMPANION_TRAP_SEED:-1}"
    python3 - "$CHECK_RUN/logs/errors.log" "$mode" <<'PY'
import sys
lines=[l for l in open(sys.argv[1]).read().splitlines() if 'COMPANION_TRAP' in l]
mode=sys.argv[2]
print('\n'.join(l for l in lines if ' tick ' not in l))
stage=next((l for l in lines if ' stage ' in l),'')
assert 'joined=1' in stage and 'leader_is_player=1' in stage, 'wolf is not a companion'
assert 'lof=0' in stage, 'companion has a line of fire; route search would be skipped'
final=next((l for l in lines if 'crossed=' in l),'')
assert final, 'no final line; fewer than 25 player actions ran'
if mode=='none': assert 'crossed=1' in final, 'control: companion never crossed with no trap'
PY
    if [ "$?" -ne 0 ]; then CHECK_FAIL=1; else CHECK_EXPECTS=$((CHECK_EXPECTS+1)); fi
done
check_done "companion crossing of a sprung, avoided and armed trap"
