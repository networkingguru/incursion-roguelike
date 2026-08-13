#!/bin/bash
# Regression check for the Error()/Fatal() defects found on 2026-08-13.
#
# Two bugs, both in src/Wlibtcod.cpp:
#
#   1. Buffer overflow. __buff2 is 80 bytes and __buffer is 1600. Error() and
#      Fatal() built their prompt with sprintf(__buff2, "...%s...", __buffer),
#      so any message longer than about 40 characters wrote past the end.
#      Observed as a segfault dereferencing 0x435b20726f207469 -- the ASCII
#      bytes "it or [C", a fragment of Error()'s own prompt string.
#
#   2. Modal freeze. Error() then blocked in a loop accepting only B, E or C.
#      Movement keys did nothing, so one bad map square froze the game. A
#      stack sample showed 1660 of 1660 samples inside Error().
#
# This is a source-invariant check, not a behavioural one: Error() is only
# reachable once the terminal is up, which needs a window and a player. It
# fails if anyone reintroduces the unbounded writes or removes the guard that
# keeps Error() non-blocking by default.
#
# Usage: tools/check_error_handling.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

# 1. No unbounded writes into the small prompt buffer.
if grep -n "sprintf(__buff2" src/*.cpp | grep -v "snprintf(__buff2" | grep -q .; then
    echo "--- offending lines ---"
    grep -n "sprintf(__buff2" src/*.cpp | grep -v "snprintf(__buff2"
    fail "sprintf into __buff2 (80 bytes) can overflow; use snprintf"
fi

# 2. No unbounded writes into the message buffer.
if grep -n "vsprintf(__buffer" src/*.cpp | grep -v "vsnprintf(__buffer" | grep -q .; then
    echo "--- offending lines ---"
    grep -n "vsprintf(__buffer" src/*.cpp | grep -v "vsnprintf(__buffer"
    fail "vsprintf into __buffer is unbounded; use vsnprintf"
fi

# 3. No caller-controlled format strings.
if grep -nE "\bprintf\(__buffer\)" src/*.cpp | grep -q .; then
    echo "--- offending lines ---"
    grep -nE "\bprintf\(__buffer\)" src/*.cpp
    fail "printf(__buffer) treats the message as a format string"
fi

# 4. Error() must return instead of blocking, unless explicitly asked not to.
if ! grep -q 'getenv("INCURSION_ERROR_PROMPT")' src/Wlibtcod.cpp; then
    fail "Error() lost its INCURSION_ERROR_PROMPT guard and will block again"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: error reporting is bounded and non-blocking by default"
    exit 0
fi
exit 1
