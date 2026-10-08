#!/bin/bash
# gate: live
# Monster::Initialize must not overflow the 63-slot action list. (bd inc-3lsp)
#
# THE DEFECT. Monster::nAct is a static counter reset only in
# Monster::ChooseAction (src/Monster.cpp). The "archer", "rogue-archer" and
# "ranger;template" templates (lib/mon2.irh) call EActor->AddAct(ACT_EQUIP) in
# their EV_INITIALIZE handler, which Monster::Initialize fires. Map::Generate
# initialises every monster of a level with no ChooseAction between them, so
# the 64th such monster fails ASSERT(nAct < 63) at inc/Creature.h:1662.
#
# THE ORACLE is INCURSION_ACT_OVERFLOW_PROBE, which arms ActOverflowProbe
# (src/ActOverflowProbe.cpp), run once at the top of Game::Play. It builds 64
# archer goblins and Initializes each, then logs
# "ACT_OVERFLOW_PROBE n=64 nAct=<n> PASS|FAIL". The check also fails on any
# "nAct < 63" ASSERT line in errors.log. A missing or unparsable probe line
# is a FAIL, never a pass.
#
# THE FIX. Monster::Initialize saves nAct before the monster's and templates'
# EV_INITIALIZE events fire and restores it after them, so init-time AddAct
# calls do not accumulate across monsters. Saving and restoring -- not zeroing
# -- matters: a monster can be Initialized in play while another monster's
# action list is being built, and that list must survive.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation below
# removes the restore line; the accumulated counter then trips ASSERT(nAct < 63)
# on the 64th Initialized archer and the probe logs nAct=64.
#
# Usage: tools/check_act_overflow.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The mutation this check defends: drop the save/restore the fix adds, so
# init-time AddAct calls accumulate again. Declared before the run below so
# --prove-red intercepts here, before the (build-needing) measurement runs.
check_mutation src/Monster.cpp \
'    nAct = savedNAct;
    ASSERT(cHP == mHP + Attr[A_THP]);' \
'    ASSERT(cHP == mHP + Attr[A_THP]);'
export INCURSION_ACT_OVERFLOW_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav

# On the defect, headless.sh ends exit 7 (an ASSERT not in
# tools/known_asserts.txt), which check_lib would read as "inconclusive". Here
# that exit IS the red result, so exit 7 passes through and the log is judged
# below. Every other bad exit keeps check_lib's verdict.
eval "_check_lib_verdict() $(declare -f _check_session_verdict | sed 1d)"
_check_session_verdict() { # <exit code> [harness output]
    [ "$1" -eq 7 ] && return 0
    _check_lib_verdict "$@"
}

check_run tools/keys/load-char-sheet.keys 1

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 \
    "the run logged nothing at all. The probe reports through Error()," \
    "so an empty log means it never ran."

if grep -q 'ACT_OVERFLOW_PROBE INCONCLUSIVE' "$LOG"; then
    grep -m1 'ACT_OVERFLOW_PROBE INCONCLUSIVE' "$LOG"
    _check_die 2 "the probe could not set up its monsters; see the line above."
fi

LINE="$(grep -v '^    ' "$LOG" | grep 'ACT_OVERFLOW_PROBE n=' | head -1)"
if [ -z "$LINE" ]; then
    echo "FAIL: no ACT_OVERFLOW_PROBE result line. Is ActOverflowProbe still"
    echo "      called from Game::Play (src/Main.cpp)?"
    grep -m3 'ACT_OVERFLOW_PROBE' "$LOG"
    exit 1
fi
NACT="$(printf '%s\n' "$LINE" | grep -oE 'nAct=-?[0-9]+' | sed 's/nAct=//')"
[ -n "$NACT" ] || { echo "FAIL: cannot parse nAct from: $LINE"; exit 1; }

ASSERTS="$(grep -c "ASSERT failed: 'nAct < 63'" "$LOG")"
echo "$LINE"
echo "nAct<63 ASSERT lines in errors.log: $ASSERTS"
echo "specimen: $LOG"
if [ "$ASSERTS" -ne 0 ] || [ "$NACT" -ge 63 ]; then
    echo "FAIL: Monster::Initialize overflowed the action list (inc-3lsp)"
    exit 1
fi
echo "PASS: 64 archer monsters Initialized without overflowing Acts"
exit 0
