#!/bin/bash
# gate: live
# A script read of a thing's map (`X->m`), while the thing is on no map, returns 0 and does not crash. (bd inc-m2c6)
#
# ORACLE: INCURSION_MAPREAD_PROBE=<varid> arms MapReadProbe() (src/MapReadProbe.cpp), run once at
# the top of Game::Play. It creates a long sword that is on no map and runs the GENERATED
# VMachine::GetMemberVar (lib/dispatch.h) on the varid of member "m". One Error() line:
#   MAPREAD_PROBE result=<value>
# ONE PROPERTY: result=0 and the run exits 0. Without the generator's null test the read
# dereferences a NULL map pointer and the run crashes with no result line.
#
# fact: the varid of "m" -- read from lib/dispatch.h (the `case N:` above the `->m` line) at run time; the check stops if it is not exactly one
# fact: the off-map item -- made by the probe; it refuses to run if the item has a map
# fact: settings -- options-2026-08-22.dat (CHECK_OPTIONS)
# fact: character and map -- fixture orc-mage-seed1-opt0822 (INCURSION_LOAD); the probe reads neither
# fact: session length -- tools/keys/monwield-probe.keys, one turn, no @expect; the probe fires before the first key
# fact: dice -- none read; a handle lookup and a pointer test
#
# Usage: tools/check_script_map_read.sh [--prove-red]   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
SEED=3
KEYS=tools/keys/monwield-probe.keys
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed1-opt0822.sav

# The mutation puts the unguarded read back in the generated code the binary compiles.
check_mutation lib/dispatch.h \
'REGS(n) = (oThing(h)->m) ? (oThing(h)->m->myHandle) : 0;' \
'REGS(n) = (oThing(h)->m->myHandle);'

VARID="$(grep -B1 -E 'oThing\(h\)->m[-)]' lib/dispatch.h | grep -oE 'case [0-9]+' | sed 's/case //')"
case "$VARID" in
    ''|*[!0-9]*) _check_die 2 "could not find exactly one varid for the thing's m in lib/dispatch.h (got: $VARID)." ;;
esac

export INCURSION_MAPREAD_PROBE="$VARID"
check_run "$KEYS" "$SEED"

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 "the run logged nothing at all; the probe reports through Error()."
grep -v '^    ' "$LOG" | grep -q "MAPREAD_PROBE INCONCLUSIVE" && _check_die 2 \
    "the probe could not set up:" "$(grep -v '^    ' "$LOG" | grep MAPREAD_PROBE)"

R="$(grep -v '^    ' "$LOG" | grep -E 'MAPREAD_PROBE result=-?[0-9]+' | head -1)"
[ -n "$R" ] || { echo "FAIL: no 'MAPREAD_PROBE result=' line; the read crashed or the probe did not run."; exit 1; }
V="$(echo "$R" | sed 's/.*result=//')"
if [ "$V" != 0 ]; then
    echo "FAIL: the off-map read returned $V; it must return NULL_OBJ (0)."
    exit 1
fi
echo "PASS: a script read of m on an off-map thing returned 0 and the run survived ($R)"
exit 0
