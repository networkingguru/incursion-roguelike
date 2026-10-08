#!/bin/bash
# gate: live
# The rejected-format path must not crash when a message is printed.
#
# src/Message.cpp __XPrint returns the CALLER'S format string when it rejects a
# format (the "Probable parameter mismatch" net, ~line 505: an <Obj> argument
# below 0x000FFFFF). That string is a read-only literal. Player::__IPrint then
# does ((char*)fm)[0] = toupper(fm[0]) on whatever __XPrint returned, so on the
# rejected path it stores through read-only memory and the process dies with
# EXC_BAD_ACCESS (SIGSEGV/SIGBUS).
#
# inc-o4y1 is a reproduction phase only: neither __IPrint nor __XPrint is
# changed. src/Main.cpp instead grows an env-gated probe that prints exactly one
# rejected-format message ("<Obj> xprint reject probe.", (Thing*)3) at the top
# of the game loop, where the player is on a map with a terminal.
#
# EXPECTED while the defect is unfixed: this check FAILS with a crash, because
# the probe drives the engine straight into the store-through-const-literal.
# Once the fix lands the same run ends cleanly and this check PASSES.
#
# Usage: tools/check_xprint_reject.sh        (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0

fail() { echo "FAIL: $*"; FAILED=1; }

RUN="$WORK/run"

# Run through tools/headless.sh and never the binary directly: only headless.sh
# gives the session its own save/ and logs/ sandbox. INCURSION_RUN_DIR pins the
# run directory so this script can read errors.log afterwards.
INCURSION_RUN_DIR="$RUN" \
INCURSION_OPTIONS="$ROOT/tools/fixtures/options-2026-08-22.dat" \
INCURSION_XPRINT_REJECT_PROBE=1 \
    tools/headless.sh tools/keys/smoke.keys 7 > "$WORK/headless.out" 2>&1
STATUS=$?

LOG="$RUN/logs/errors.log"

echo "--- headless.sh session (probe on) exit $STATUS ---"
tail -20 "$WORK/headless.out"

# 1. The session must not crash. Under headless.sh the crash surface is either
#    the raw signal code (138 SIGBUS / 139 SIGSEGV) or the "ended: exit N" line.
if [ "$STATUS" -ne 0 ]; then
    case $STATUS in
        138) fail "SIGBUS: the rejected-format store hit read-only memory (exit $STATUS)" ;;
        139) fail "SIGSEGV: the rejected-format store hit read-only memory (exit $STATUS)" ;;
        *)   fail "the session exited $STATUS, wanted 0 (see headless.sh above for the signal)" ;;
    esac
fi

# 2. The net must actually have caught the probe, or this proves nothing. The
#    error line proves the probe fired AND __XPrint rejected it -- both halves.
#    grep -c prints 0 AND exits 1 on no match, so `|| true` keeps the 0.
count_in_log() {
    local n
    n="$(grep -c "$1" "$LOG" 2>/dev/null || true)"
    echo "${n:-0}"
}

MATCHED="$(count_in_log 'Probable parameter mismatch')"
PROBE_FIRED="$(count_in_log 'xprint reject probe')"
if [ "$MATCHED" -eq 0 ]; then
    fail "errors.log has no 'Probable parameter mismatch' line; __XPrint never rejected the probe"
fi
if [ "$PROBE_FIRED" -eq 0 ]; then
    fail "errors.log has no 'xprint reject probe' line; the probe never fired"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: the rejected format was caught, reported, and the session ended cleanly"
    exit 0
fi
exit 1
