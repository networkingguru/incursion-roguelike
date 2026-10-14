#!/bin/bash
# gate: live
# The wizard menu's "All Monster Aggravate" and "All Monsters Retarget" entries
# must run to completion without crashing the session. (bd inc-hy9u)
#
# THE DEFECT. src/Debug.cpp case 29 (the "All Monster Aggravate" wizard entry)
# calls Monster::GainPermStati with myHandle -- an object handle -- as the
# sixth argument, `rID eID`, which is a RESOURCE id (inc/Map.h). Thing::
# GainPermStati then runs ASSERT(theGame->Get(eID)) (src/Status.cpp:197) on a
# number that names no resource; Game::Get logs "resource id 129 names module
# slot -1, out of range" and the process segfaults.
#
# THE ORACLE is the after-turn screen dump written by the reproduction key
# script tools/keys/wizard-aggravate.keys, plus errors.log. Acceptance
# criterion 1 asks that BOTH wizard commands run in sequence: the script fires
# "All Monster Aggravate" (case 29) then "All Monsters Retarget" (case 26). On
# the fixed build the aggravate completes, the retarget runs, the next turn is
# taken and @dump:after-turn writes a screen; errors.log carries neither the
# ASSERT line nor the "names module slot -1" line. On the defect the session
# crashes before that dump, and both log lines are present. Retarget itself
# had no defect, so the mutation below (Aggravate's myHandle) is still the
# only red. A missing dump or a missing log is a FAIL or INCONCLUSIVE, never a
# pass.
#
# THE FIX. Pass 0 there instead of myHandle, the same shape as src/Main.cpp:937
# and src/Player.cpp:222: no resource, which is what an ENEMY_TO perm stati on
# an arbitrary monster needs.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation below
# restores myHandle in place of the fix's 0; the aggravate then reads the
# missing resource, the ASSERT fires and the session segfaults.
#
# Usage: tools/check_wizard_aggravate.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The mutation this check defends: put myHandle back where the fix passes 0.
# Declared before the run below so --prove-red intercepts here, before the
# (build-needing) measurement runs.
check_mutation src/Debug.cpp \
'                ((Monster *)t)->GainPermStati(ENEMY_TO,t,SS_PERM,-1,-1,
                0,9);' \
'                ((Monster *)t)->GainPermStati(ENEMY_TO,t,SS_PERM,-1,-1,
                myHandle,9);'

# On the defect, headless.sh ends exit 139 (SIGSEGV), which check_lib would
# read as "inconclusive". Here that exit IS the red result, so it passes
# through to the log judgement below. Every other bad exit keeps check_lib's
# verdict.
eval "_check_lib_verdict() $(declare -f _check_session_verdict | sed 1d)"
_check_session_verdict() { # <exit code> [harness output]
    [ "$1" -ge 128 ] && return 0
    _check_lib_verdict "$@"
}

check_run tools/keys/wizard-aggravate.keys 5

LOG="$CHECK_RUN/logs/errors.log"
DUMP="$(ls "$CHECK_RUN"/logs/screens/*-after-turn.txt 2>/dev/null | head -1)"
RETARGET="$(ls "$CHECK_RUN"/logs/screens/*-after-retarget.txt 2>/dev/null | head -1)"

# A clean run writes no errors.log at all; only a failing one does, so a
# missing file is not itself a failure. When it exists, neither of the two
# crash lines may appear in it.
ASSERT=0
BADRID=0
if [ -f "$LOG" ]; then
    ASSERT="$(grep -c "ASSERT failed: 'theGame->Get(eID)'" "$LOG")"
    BADRID="$(grep -c 'names module slot -1, out of range' "$LOG")"
fi
echo "theGame->Get(eID) ASSERT lines in errors.log: $ASSERT"
echo "names module slot -1 lines in errors.log:     $BADRID"

if [ "$ASSERT" -ne 0 ] || [ "$BADRID" -ne 0 ]; then
    echo "FAIL: All Monster Aggravate read a missing resource and crashed (inc-hy9u)"
    grep -m2 'theGame->Get\|names module slot -1' "$LOG"
    echo "specimen: $LOG"
    exit 1
fi

[ -f "$DUMP" ] || {
    echo "FAIL: the after-turn dump was never written ($DUMP). The session did"
    echo "      not survive the aggravate to take its next turn."
    echo "specimen: $CHECK_RUN"
    exit 1
}
[ -f "$RETARGET" ] || {
    echo "FAIL: the after-retarget dump was never written ($RETARGET). The"
    echo "      session did not survive 'All Monsters Retarget'."
    echo "specimen: $CHECK_RUN"
    exit 1
}
echo "specimen: $DUMP"
echo "specimen: $RETARGET"
echo "PASS: All Monster Aggravate and All Monsters Retarget completed; the next turn was taken"
exit 0
