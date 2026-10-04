#!/bin/bash
# gate: live
# inc-e3oo: real TryToDestroyThing selection, intercepted before spell dispatch.
# Exit 0 pass, 1 wrong selection, 2 missing/incomplete measurement.
case "${1:-}" in
    --selftest) exec python3 "$(dirname "$0")/check_autoknock.py" --selftest ;;
esac
. "$(dirname "$0")/check_lib.sh"
CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_AUTOKNOCK_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed1-opt0822.sav
check_run tools/keys/door-pick-kick.keys 1 > /dev/null || exit $?
LOG="$CHECK_RUN/logs/autoknock.log"
echo "probe log: $LOG"
python3 tools/check_autoknock.py "$LOG"
exit $?
