#!/bin/bash
# gate: cheap
# Does src/FmtCheck.cpp reject every pointer-reading script tag and unsafe
# printf conversion, and accept every handle-safe one?
#
# inc-ac0l phase 1 of 3. A script string or object argument is an int32 handle;
# __XPrint (src/Message.cpp:146-164, :474-497) reads a <str...> tag as
# const char* and an <obj|mon|itm...> tag as Thing*, so a script that uses
# those tags crashes the game. ScriptFormatProblem (src/FmtCheck.cpp) is the
# shared scanner that later phases call from the generated script dispatch.
# This check compiles that file with tools/fmtcheck_selftest.cpp and runs every
# asserted case. No game build, no terminal.
#
# Usage: tools/check_fmtcheck.sh        (exit 0 pass, 1 fail, 2 could not build)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

CXX="${CXX:-c++}"
command -v "$CXX" >/dev/null 2>&1 || { echo "COULD NOT MEASURE: $CXX missing"; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

INCLUDES="-Iinc -Ilib -Icompat"

# shellcheck disable=SC2086
if ! "$CXX" -std=c++14 -w $INCLUDES \
        "$ROOT/src/FmtCheck.cpp" "$ROOT/tools/fmtcheck_selftest.cpp" \
        -o "$WORK/fmtcheck_selftest" 2> "$WORK/build.log"; then
    echo "COULD NOT MEASURE: self-test did not compile"
    sed -n '1,40p' "$WORK/build.log"
    exit 2
fi

if "$WORK/fmtcheck_selftest"; then
    echo "PASS  FmtCheck self-test"
    exit 0
else
    echo "FAIL  FmtCheck self-test"
    exit 1
fi
