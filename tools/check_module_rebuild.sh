#!/bin/bash
# Does an ordinary build put THIS tree's scripts into the game?
#
# Usage: tools/check_module_rebuild.sh
# Exit:  0 it does, and an instrumented build still leaves the module alone
#        1 IT DOES NOT -- a script-only fix would build clean and change nothing
#        2 nothing was measured, and the reason is printed
#
# WHAT THIS IS FOR. mod/Incursion.Mod holds the compiled game scripts. Registry
# stamps every file with a layout digest (src/Registry.cpp:65) and refuses a
# module built by a different struct layout, so THAT mistake is caught. A module
# with the right layout and last week's rules is not caught: it loads in
# silence. build_macos.sh used to compile it only when the file was ABSENT, so
# editing lib/*.irh and running the documented build command produced a clean
# build that still ran the old script. That happened twice on 2026-08-22 and was
# nearly reported as a fix. See inc-nx6c.
#
# WHY IT BUILDS TWICE. The repair has two halves and one without the other is
# useless. An ordinary developer build must recompile the module every time.
# An instrumented build (EXTRA_CXXFLAGS set) must NOT: it shares this one module
# file with the ordinary build, so a flag that moved a struct would leave behind
# a module the ordinary binary then refuses to load. The second half is the
# control, and it is why this check cannot be passed by compiling unconditionally.
#
# It costs two builds. Run it when build_macos.sh changes, not on every commit.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MOD="$ROOT/mod/Incursion.Mod"
LOG="$(mktemp -t modrebuild)"

[ -f "$MOD" ] || {
    echo "COULD NOT MEASURE: no mod/Incursion.Mod to begin with."
    echo "  This check asks whether an EXISTING module is refreshed. Build once"
    echo "  first: BACKEND=posix ./build_macos.sh"
    exit 2
}

stamp() { stat -f '%m' "$MOD"; }

# ---- half one: an ordinary build must refresh it ------------------------
before="$(stamp)"
if ! BACKEND=posix ./build_macos.sh > "$LOG" 2>&1; then
    echo "COULD NOT MEASURE: the ordinary build failed. Its output:"
    tail -20 "$LOG"
    exit 2
fi
after="$(stamp)"

if [ "$before" = "$after" ]; then
    echo "FAIL -- an ordinary build left mod/Incursion.Mod untouched."
    echo "        A change to any lib/*.irh would not reach the game, and the"
    echo "        build would still exit 0. See inc-nx6c."
    exit 1
fi
echo "ok:   an ordinary build recompiled the module"

# ---- half two: an instrumented build must not touch it ------------------
before="$(stamp)"
if ! EXTRA_CXXFLAGS=-DDIVERGE_PROBE OUT=incursion-probe BACKEND=posix \
        ./build_macos.sh > "$LOG" 2>&1; then
    echo "COULD NOT MEASURE: the instrumented build failed. Its output:"
    tail -20 "$LOG"
    exit 2
fi
after="$(stamp)"

if [ "$before" != "$after" ]; then
    echo "FAIL -- an instrumented build rewrote mod/Incursion.Mod."
    echo "        A diagnostic flag that moves a struct would then leave a module"
    echo "        the ordinary binary refuses to load. See inc-nx6c."
    exit 1
fi
echo "ok:   an instrumented build left the module alone"

rm -f "$LOG"
echo
echo "PASS -- this tree's scripts reach the game, and diagnostic builds do not"
echo "        overwrite the module they share."
exit 0
