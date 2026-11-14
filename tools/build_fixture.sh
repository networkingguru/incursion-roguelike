#!/bin/bash
# Build a character from a .char file: the same Game::NewGame a player runs,
# answered by the File creation source instead of the screens (bead inc-10v7f,
# spec sections 3 and 5). The result is <name>.sav and <name>.sheet.txt.
#
# Usage: tools/build_fixture.sh <file.char> [out-dir]
#        tools/build_fixture.sh tools/fixtures/chars/orc-barbarian-seed1-opt0822.char
#
# out-dir defaults to logs/fixture-build/<name>/. <name> is the .char file's
# base name.
#
# SANDBOX. The build runs `incursion-headless -build` in a run directory of its
# own, made the way tools/headless.sh makes one: its own save/ and logs/,
# mod/ and lib/ linked in. The binary is NEVER run from the repo root, so a
# build cannot touch a real save/. The binary reads the file's options: and
# seed: lines itself (src/CharFile.cpp, CharFilePrepare); this script names
# no decision key.
#
# THE ENVIRONMENT. Only INCURSION_BIN (which binary), INCURSION_BUILD_RUN_DIR
# (where the sandbox lives) and INCURSION_BUILD_MEM_CAP_MB (the memory cap, below)
# are read. A run directory the caller names is the
# caller's: this script neither empties it first nor removes it after, so a test
# can put a gallery.dat there beforehand and read the sandbox afterwards.
# INCURSION_SEED, INCURSION_RECORD_CHAR and every other INCURSION_* variable is
# removed before the binary starts, so a stray variable in the caller's shell
# cannot change the character. The seed comes from the file. The one variable
# kept are INCURSION_TRIPWIRE_PROBE (a test hook, see below) and INCURSION_MAP_STREAM.
#
# MEMORY CAP (bead inc-r10je). A build that loops grows about 650 MB a second
# (inc-xgs1x). Each half second this script sums the resident memory of the
# binary and its child processes. At INCURSION_BUILD_MEM_CAP_MB (default 2048) it
# kills them and exits 10 with a BUILD FAILED line that names the cap. When
# memory cannot be read it kills the build too: it never runs uncapped. The sum
# comes from tools/proc_tree_rss.py (libproc), not ps: a sandbox cannot exec ps.
#
# Exit: 0 built; 2 bad usage (a cap that is not a positive integer too); 10 the build failed (the BUILD FAILED line is on
# stderr); any other code is the binary's.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

# Read before the INCURSION_* scrub below: the binary must not see the cap.
MEM_CAP_MB="${INCURSION_BUILD_MEM_CAP_MB:-2048}"
case "$MEM_CAP_MB" in
    ''|*[!0-9]*|0|0[0-9]*)
        echo "INCURSION_BUILD_MEM_CAP_MB must be a positive integer, got \"$MEM_CAP_MB\"" >&2
        exit 2 ;;
esac

CHAR="${1:-}"
if [ -z "$CHAR" ] || [ ! -f "$CHAR" ]; then
    echo "usage: tools/build_fixture.sh <file.char> [out-dir]" >&2
    exit 2
fi
NAME="$(basename "$CHAR" .char)"
OUT="${2:-logs/fixture-build/$NAME}"
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "$BIN not built. Run: BACKEND=posix ./build_macos.sh" >&2; exit 2; }

CHAR="$(cd "$(dirname "$CHAR")" && pwd)/$(basename "$CHAR")"
mkdir -p "$OUT" || exit 2
OUT="$(cd "$OUT" && pwd)"

OWN_RUN=1
RUN="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-build-$NAME"
if [ -n "${INCURSION_BUILD_RUN_DIR:-}" ]; then
    OWN_RUN=0
    RUN="$INCURSION_BUILD_RUN_DIR"
fi
mkdir -p "$RUN/save" "$RUN/logs"
ln -sfn "$ROOT/mod" "$RUN/mod"
ln -sfn "$ROOT/lib" "$RUN/lib"

# The sandbox is the binary's whole world. Every INCURSION_* variable goes.
CLEAN=()
# INCURSION_TRIPWIRE_PROBE is the one exception: tools/check_fixture_tripwires.sh
# sets it to insert a fault and prove a tripwire fires. Unset it changes nothing.
# INCURSION_MAP_STREAM is the other: tools/char_arrive.sh sets it so the build makes
# the map the walk made (src/Main.cpp, Game::NewGameTail). Unset it changes nothing.
while IFS= read -r v; do
    [ "$v" = INCURSION_TRIPWIRE_PROBE ] && continue
    [ "$v" = INCURSION_MAP_STREAM ] && continue
    CLEAN+=(-u "$v")
done < <(env | sed -n 's/^\(INCURSION[A-Z0-9_]*\)=.*/\1/p')

env ${CLEAN[@]+"${CLEAN[@]}"} INCURSIONPATH="$RUN/" "$BIN" -headless -build "$CHAR" \
    > "$RUN/logs/build.out" 2> "$RUN/logs/build.err" < /dev/null &
BPID=$!
T0=$SECONDS
CAP_MSG=""
while kill -0 "$BPID" 2> /dev/null; do
    TREE="$(python3 -I "$ROOT/tools/proc_tree_rss.py" "$BPID" 2> /dev/null)"
    if [ -z "$TREE" ]; then
        # The build may have exited since the loop test; only a live build is a failure.
        kill -0 "$BPID" 2> /dev/null || break
        kill -9 "$BPID" 2> /dev/null
        CAP_MSG="BUILD FAILED: the memory cap of $MEM_CAP_MB MB cannot run: process memory cannot be read (tools/proc_tree_rss.py)"
        break
    fi
    MB="${TREE%% *}"
    if [ "${MB:-0}" -ge "$MEM_CAP_MB" ]; then
        for k in ${TREE#* }; do kill -9 "$k" 2> /dev/null; done
        CAP_MSG="BUILD FAILED: the build passed the memory cap of $MEM_CAP_MB MB (${MB} MB after $((SECONDS - T0)) s); a creation step is probably looping"
        break
    fi
    sleep 0.5
done
wait "$BPID" 2> /dev/null
STATUS=$?
if [ -n "$CAP_MSG" ]; then
    echo "$CAP_MSG" >&2
    echo "build_fixture: $NAME did not build; run directory $RUN" >&2
    exit 10
fi
cat "$RUN/logs/build.err" >&2
if [ "$STATUS" -ne 0 ]; then
    echo "build_fixture: $NAME did not build (exit $STATUS); run directory $RUN" >&2
    exit "$STATUS"
fi

SAV="$(ls -t "$RUN"/save/*.sav 2>/dev/null | head -1)"
SHEET="$RUN/logs/sheet.txt"
if [ -z "$SAV" ] || [ ! -f "$SHEET" ]; then
    echo "BUILD FAILED: the build exited 0 but left no .sav or no sheet ($RUN)" >&2
    exit 10
fi
cp -f "$SAV" "$OUT/$NAME.sav" || exit 2
cp -f "$SHEET" "$OUT/$NAME.sheet.txt" || exit 2
echo "built $OUT/$NAME.sav"
[ "$OWN_RUN" -eq 1 ] && rm -rf "$RUN"
exit 0
