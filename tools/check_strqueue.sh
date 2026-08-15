#!/bin/bash
# The string queue must not be written past its end.
#
# src/Base.cpp keeps every temporary String in StrBufDelQueue so PurgeStrings()
# can free them later. The bound on that array used to be tested AFTER the
# write, as an ASSERT -- and ASSERT in this codebase only calls Error(), which
# logs and returns. So a full queue wrote one pointer past the end of a 64000
# entry global on every call, reporting the same failed assert each time and
# changing nothing, until the process died on a wild address.
#
# That is not hypothetical. It killed a real session on 2026-08-15 09:27:
# twelve identical assert lines in one second, then SIGSEGV. No soak had ever
# produced it, because PurgeStrings() is driven by drawing and only a long
# monster pathfind allocates 64000 temporaries between two draws.
#
# Waiting for that in a test would take a very large level and a lot of luck.
# STRING_QUEUE_SIZE is overridable instead, so this builds a probe with a queue
# of 400 and fills it in seconds.
#
# Proven to fail without the fix: the same probe built from the code as it was
# exits 138 (SIGBUS) with 12 assert lines, which is the same signature as the
# session that died.
#
# Usage: tools/check_strqueue.sh        (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0

fail() { echo "FAIL: $*"; FAILED=1; }

echo "building a probe with STRING_QUEUE_SIZE=400 ..."
if ! EXTRA_CXXFLAGS="-DSTRING_QUEUE_SIZE=400" BACKEND=posix \
     OUT=incursion-strqueue ./build_macos.sh > "$WORK/build.log" 2>&1; then
    echo "--- build output ---"
    tail -15 "$WORK/build.log"
    fail "the probe did not build"
    exit 1
fi

mkdir -p "$WORK/run/logs" "$WORK/run/save"
ln -sfn "$ROOT/mod" "$WORK/run/mod"
ln -sfn "$ROOT/lib" "$WORK/run/lib"
[ -f "$ROOT/Options.Dat" ] && cp "$ROOT/Options.Dat" "$WORK/run/Options.Dat"

INCURSIONPATH="$WORK/run/" INCURSION_SEED=7 \
    ./incursion-strqueue -keys tools/keys/smoke.keys \
    < /dev/null > "$WORK/session.out" 2>&1
STATUS=$?

LOG="$WORK/run/logs/errors.log"

# 1. The session must survive a full queue. Without the bound this is a crash.
if [ "$STATUS" -ne 0 ]; then
    echo "--- session output ---"
    tail -10 "$WORK/session.out"
    case $STATUS in
        138) fail "SIGBUS: the queue was written past its end (exit $STATUS)" ;;
        139) fail "SIGSEGV: the queue was written past its end (exit $STATUS)" ;;
        *)   fail "the session exited $STATUS, wanted 0" ;;
    esac
fi

# grep -c prints 0 AND exits 1 when it matches nothing, so `|| echo 0` appends a
# second line and every later [ -eq ] dies with "integer expression expected" --
# which bash reports and the script then sails past, printing PASS on a check
# that never ran. `|| true` keeps the 0 and drops the failure.
count_in_log() {
    local n
    n="$(grep -c "$1" "$LOG" 2>/dev/null || true)"
    echo "${n:-0}"
}

# 2. The queue must actually have filled, or this proves nothing at all.
FULL="$(count_in_log 'String queue is full')"
if [ "$FULL" -eq 0 ]; then
    fail "the queue never filled, so the bound was never exercised"
fi

# 3. Reported once, not once per call. Twelve lines a second is its own defect.
if [ "$FULL" -gt 1 ]; then
    fail "the full queue was reported $FULL times, wanted once"
fi

# 4. The old failing assert must not appear at all.
OLD="$(count_in_log 'iStrBufDelQueue')"
if [ "$OLD" -ne 0 ]; then
    fail "the old bound assert fired $OLD times; the check is still after the write"
fi

rm -f ./incursion-strqueue

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: a full string queue leaks a string, says so once, and plays on"
    exit 0
fi
exit 1
