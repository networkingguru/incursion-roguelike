#!/bin/bash
# Print a plain-text character report for a .sav file, without playing the
# game and without touching the real save/ directory.
#
# Usage: tools/dump_save.sh <save-file> [save-file-in-sandbox-name]
#        tools/dump_save.sh save/Jaoin.sav
#        tools/dump_save.sh /tmp/some_copy.sav
#
# WHAT THIS IS FOR. bd inc-loa.1: an oracle session, or a person, asking what
# a real character is carrying, what stati she is under, or what the game
# thinks her weapon skill is -- read-only, without running the game any other
# way. The report comes from -dump (src/Dump.cpp), a mode of the game binary
# itself: it loads the file through the real Registry::LoadGroup and walks it
# with the real accessors, which is the only way the report cannot drift out
# of step with the save format. See docs/ENGINE-SERIALISATION.md for why an
# external parser was rejected outright.
#
# SAFETY. -dump opens the named file and the save's module dependencies for
# reading only: it never calls OpenWrite, never calls Player::TouchGallery,
# and never calls Game::SaveGame (see the header comment on src/Dump.cpp for
# the exact claim). This wrapper adds a second, independent layer on top of
# that, the same way tools/headless.sh does for a played session: the game is
# pointed at an empty, disposable sandbox directory via INCURSIONPATH, with
# mod/ and lib/ symlinked in read-only, so that even a defect that made -dump
# write something would land in a throwaway directory and never in the real
# save/. Point ANYTHING that runs this binary -- the oracle brief included --
# at this wrapper, never at the binary directly.
#
# The .sav file itself is still opened wherever it is. Passing a path inside
# the game's own save/ directory is safe -- -dump never writes -- but pass a
# COPY if you want to be doubly sure, or if you are handing this to something
# you have not read the safety claim of yourself.
#
# Exit: 0 the report printed. Any other code: -dump refused the file (a
#       version mismatch says which format it wanted) or the file does not
#       exist; see stderr.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SAVE="${1:-}"
if [ -z "$SAVE" ] || [ ! -f "$SAVE" ]; then
    echo "usage: tools/dump_save.sh <save-file>"
    exit 2
fi
# -dump takes whatever path it is given, relative to wherever this script's
# caller is standing; resolve it to an absolute path before the sandbox
# below chdir()s the binary out from under a relative one.
SAVE="$(cd "$(dirname "$SAVE")" && pwd)/$(basename "$SAVE")"

# See tools/headless.sh for the reasoning behind INCURSION_BIN and why a
# launcher, if given one, must not be trusted for its own exit code.
#
# Either binary works. ./incursion-headless stays the default because it needs
# no SDL and is what a harness has to hand, but since 2026-08-18 the graphical
# ./incursion parses -dump too (src/Wlibtcod.cpp main(), mirroring
# src/Wposix.cpp:530-539) and prints a byte-identical report -- both walk the
# same src/Dump.cpp, and tools/check_dump_save.sh asserts they agree. So a
# person with only the release build can inspect a save without building a
# second binary: INCURSION_BIN=./incursion tools/dump_save.sh <save>
BIN="${INCURSION_BIN:-./incursion-headless}"
LAUNCHER="${INCURSION_LAUNCHER:-}"

[ -x "$BIN" ] || {
    echo "$BIN not built. Run: BACKEND=posix ./build_macos.sh"
    echo "Or use the graphical build: INCURSION_BIN=./incursion $0 <save>"
    exit 2
}

SANDBOX="${INCURSION_DUMP_SANDBOX:-$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-dump}"
mkdir -p "$SANDBOX/save" "$SANDBOX/logs"
ln -sfn "$ROOT/mod" "$SANDBOX/mod"
ln -sfn "$ROOT/lib" "$SANDBOX/lib"

INCURSIONPATH="$SANDBOX/" $LAUNCHER "$BIN" -dump "$SAVE"
STATUS=$?

# A clean run leaves the sandbox's save/ and logs/ empty. If it does not,
# that is exactly the safety claim failing, and the directory is left in
# place (not cleaned up) so the failure can be inspected rather than erased.
LEFTOVERS="$(find "$SANDBOX/save" "$SANDBOX/logs" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$LEFTOVERS" != "0" ]; then
    echo "incursion -dump: SAFETY CLAIM FAILED -- $LEFTOVERS file(s) were" >&2
    echo "written under $SANDBOX. Left in place for inspection." >&2
    find "$SANDBOX/save" "$SANDBOX/logs" -type f >&2
    [ "$STATUS" -eq 0 ] && STATUS=1
else
    rm -rf "$SANDBOX"
fi

exit $STATUS
