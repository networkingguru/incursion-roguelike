#!/bin/bash
# Regression check for the type-width and handle/pointer confusion bug classes.
#
# Two separate checks, because the two classes fail in different ways.
#
# 1. WIDTHS. src/AbiCheck.cpp asserts, at compile time, every type width the
#    save format depends on. A width change is invisible at run time until it
#    corrupts data -- that is how *((long*)&hm) zeroed every saved player
#    position without one error message. This step just compiles that file.
#    It is also compiled by the normal build, so a green build already implies
#    a green step 1; the step exists so this script can be run on its own.
#
# 2. HANDLE/POINTER CONFUSION. hObj, hData, rID and friends are 4-byte indices
#    into the Registry, never addresses. Casting one to an object pointer and
#    dereferencing it gives a wild pointer. clang reports every instance with
#    -Wint-to-pointer-cast, but the build passes -w, so the warnings never
#    appear. This step re-runs the compiler with just those two warnings on.
#
# The KNOWN list below is an allowlist of sites that are already reported and
# accepted. It held two entries when this check was written; both were fixed
# under inc-upw.1 / gh-5, so it is now empty. Keep it that way -- a new hit is
# a bug to fix, not an entry to add.
#
# Usage: tools/check_abi.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KNOWN=""

command -v pkg-config >/dev/null || { echo "FAIL: pkg-config not found"; exit 1; }
SDL_CFLAGS="$(pkg-config --cflags sdl2)" || { echo "FAIL: sdl2 not installed"; exit 1; }
INCLUDES="-Iinc -Ilib -Ilibtcod/include -Icompat $SDL_CFLAGS"
DEFINES="-DDEBUG -DLIBTCOD_TERM"

# --- 1. widths -------------------------------------------------------------
OUT="$(clang++ -std=c++17 -fsyntax-only -fpermissive -w \
        $DEFINES $INCLUDES src/AbiCheck.cpp 2>&1)"
if [ -n "$OUT" ]; then
    echo "FAIL: a type width the save format depends on has changed."
    echo "$OUT"
    echo "Read the header of src/AbiCheck.cpp before relaxing any assertion."
    exit 1
fi
echo "PASS: type widths match what the save format expects"

# --- 2. handle/pointer confusion -------------------------------------------
sweep() {
    local f n std
    for f in src/*.cpp; do
        n="$(basename "$f" .cpp)"
        # Wcurses is the Windows/pdcurses backend and is not built on POSIX.
        if [ "$n" = "Wcurses" ]; then continue; fi
        # Tokens and Art are flex/ACCENT output and use the removed `register`.
        std="c++17"
        if [ "$n" = "Tokens" ] || [ "$n" = "Art" ]; then std="c++14"; fi
        clang++ -std=$std -fsyntax-only -fpermissive \
            -Wno-everything -Wint-to-pointer-cast -Wpointer-to-int-cast \
            $DEFINES $INCLUDES "$f" 2>&1
    done
}

FOUND="$(sweep | grep "warning:" | cut -d: -f1,2 | sort -u | grep . || true)"
ALLOWED="$(echo "$KNOWN" | sort -u | grep . || true)"

NEW="$(comm -23 <(echo "$FOUND") <(echo "$ALLOWED"))"
if [ -n "$NEW" ]; then
    echo "FAIL: a handle is cast to a pointer at a new site:"
    echo "$NEW" | sed 's/^/  /'
    echo "A handle is an index into the Registry. Resolve it with oThing(),"
    echo "oItem(), oMap() and so on; never cast it."
    exit 1
fi

# An allowlist entry that no longer matches is stale. Say so, so the list does
# not quietly outlive the bug it was recording.
GONE="$(comm -13 <(echo "$FOUND") <(echo "$ALLOWED"))"
if [ -n "$GONE" ]; then
    echo "PASS: no handle/pointer casts outside the allowlist."
    echo "      These allowlist entries no longer match anything:"
    echo "$GONE" | sed 's/^/        /'
    echo "      Delete them from KNOWN in this script."
elif [ -n "$ALLOWED" ]; then
    echo "PASS: no new handle/pointer casts ($(echo "$ALLOWED" | wc -l | tr -d ' ') allowlisted, see inc-upw.1)"
else
    echo "PASS: no handle is cast to a pointer anywhere in src/"
fi
exit 0
