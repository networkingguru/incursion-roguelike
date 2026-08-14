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
# The KNOWN list below records the sites that already existed when this check
# was written. Both are tracked as inc-upw.1 / gh-5. When that is fixed, empty
# the list -- do not add new entries to it.
#
# Usage: tools/check_abi.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KNOWN="src/Effects.cpp:1294
src/Managers.cpp:520"

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

FOUND="$(sweep | grep "warning:" | cut -d: -f1,2 | sort -u)"

NEW="$(comm -23 <(echo "$FOUND" | grep . | sort -u) <(echo "$KNOWN" | sort -u))"

if [ -n "$NEW" ]; then
    echo "FAIL: a handle is cast to a pointer at a new site:"
    echo "$NEW" | sed 's/^/  /'
    echo "A handle is an index into the Registry. Resolve it with oThing(),"
    echo "oItem(), oMap() and so on; never cast it."
    exit 1
fi

GONE="$(comm -13 <(echo "$FOUND" | grep . | sort -u) <(echo "$KNOWN" | sort -u))"
if [ -n "$GONE" ]; then
    echo "PASS: no new handle/pointer casts (and these known ones are now gone:"
    echo "$GONE" | sed 's/^/  /'
    echo " -- remove them from KNOWN in this script)"
else
    echo "PASS: no new handle/pointer casts (2 known sites remain, see inc-upw.1)"
fi
exit 0
