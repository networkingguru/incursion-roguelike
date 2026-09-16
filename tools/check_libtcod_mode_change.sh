#!/usr/bin/env bash
# gate: none needs a real display and opens a fullscreen window
#
# Does libtcod recalculate its copy rectangle after a display mode change?
#
# inc-i2h1. Vendored libtcod 1.6.3 kept a file-scope copy rectangle that
# outlived the window it described, so the console stayed clipped to the old
# window's pixel size after Alt-Enter or after an Options-manager resize.
# tools/libtcod_mode_change_probe.c says why neither a key script nor @shot
# can see this.
#
# Usage: tools/check_libtcod_mode_change.sh              (exits 0 on pass, 1 on fail)
#        tools/check_libtcod_mode_change.sh --selftest   (proves the harness can fail)
#
# Exit: 0 pass, 1 fail, 2 could not measure.
#
# Do not run this while anyone is playing: phase C takes over the screen with
# a fullscreen window for a moment.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SELFTEST=""
if [ "${1:-}" = "--selftest" ]; then SELFTEST="--selftest"; fi

TCODLIB="build/libtcod_local.a"
if [ ! -f "$TCODLIB" ]; then
    echo "INCONCLUSIVE: $TCODLIB is missing; run ./build_macos.sh first" >&2
    exit 2
fi
if ! pkg-config --exists sdl2; then
    echo "INCONCLUSIVE: pkg-config cannot find sdl2" >&2
    exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-tcodmode.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/probe"

CC="${CC:-cc}"
# The same defines build_macos.sh:288 builds the vendored library with; without
# them the headers describe a different library from the one we link.
if ! "$CC" -O0 -g -DTCOD_SDL2 -DNO_OPENGL \
        $(pkg-config --cflags sdl2) -Ilibtcod/include -Ilibtcod/src \
        -o "$BIN" tools/libtcod_mode_change_probe.c "$TCODLIB" \
        $(pkg-config --libs sdl2) -lz 2> "$WORK/build.log"; then
    echo "FAIL: could not build the libtcod mode-change probe" >&2
    cat "$WORK/build.log" >&2
    exit 1
fi

# libtcod chatters about fonts and renderers on stdout; keep the numbers.
OUT="$WORK/probe.log"
"$BIN" $SELFTEST > "$OUT" 2>&1
STATUS=$?
grep -E "^(  |FAIL)" "$OUT"

if [ "$SELFTEST" = "--selftest" ]; then
    if [ "$STATUS" -eq 0 ]; then
        echo "FAIL: --selftest asserted something false and the check still passed" >&2
        exit 1
    fi
    echo "PASS: --selftest failed as it must"
    exit 0
fi

if [ "$STATUS" -ne 0 ]; then
    echo "FAIL: libtcod did not recalculate its copy rectangle after a mode change" >&2
    exit 1
fi
echo "PASS: the copy rectangle follows the console across a mode change, and a fullscreen window reports itself fullscreen"
exit 0
