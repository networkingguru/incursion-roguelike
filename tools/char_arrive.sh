#!/usr/bin/env bash
# Build a `.char`, play the arrival on the built character, dump the result
# (bead inc-10v7f, phase 11g). tools/char_convert.sh and tools/char_attribute.sh
# call this one script, so both compare exactly the same thing.
#
# An old .sav was written by its key script AFTER creation ended: the game loop
# began on level 1, turns passed, then the script saved. A built character is
# saved at the end of creation, before any turn. So the built character is
# loaded, the part of the key script that ran after creation is played on it
# (tools/headless.sh with INCURSION_LOAD and INCURSION_KEYS_SKIP), it saves as
# the script saves, and THAT save is dumped. See tools/char_convert.sh, THE
# ARRIVAL, for where <skip> and <tick> come from.
#
# Usage: tools/char_arrive.sh <char> <prefix> <keys> <seed> <options> <skip|-> <tick|-> [<stream>]
#        INCURSION_BIN=<binary>   the binary (default ./incursion-headless)
#   <prefix>   writes <prefix>-out/ (the build), <prefix>-build.log,
#              <prefix>-load.sav (the built save), <prefix>-replay/ and
#              <prefix>-replay.log (the replay's run), and <prefix>.canon (the dump).
#   <skip>     the number of script entries creation consumed; `-` plays no
#              replay and dumps the built save itself (a .char with no arrival).
#   <tick>     the seed tick of the walk (INCURSION_SEED_TICK); `-` with `-` skip.
#   <stream>   the random-stream position the walk stood at when it made its map,
#              `<tick>:<seed>:<draws>` (<walk>.stream, src/Main.cpp NewGameTail);
#              the build stands there before it makes the map (INCURSION_MAP_STREAM),
#              so it makes the walk's map. `-` or absent: the build makes its own.
# Exit: 0 <prefix>.canon written; 2 could not (the reason is the one stderr line).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
CHAR="${1:-}"; PFX="${2:-}"; KEYS="${3:-}"; SEED="${4:-}"; OPTS="${5:-}"; SKIP="${6:-}"; TICK="${7:-}"; STREAM="${8:--}"
if [ -z "$CHAR" ] || [ -z "$PFX" ] || [ -z "$SKIP" ] || [ -z "$TICK" ] || [ -z "$OPTS" ]; then
    echo "usage: tools/char_arrive.sh <char> <prefix> <keys> <seed> <options> <skip|-> <tick|->" >&2
    exit 2
fi
mkdir -p "$(dirname "$PFX")" || exit 2
PFX="$(cd "$(dirname "$PFX")" && pwd)/$(basename "$PFX")"
LOAD="$PFX-load.sav"; RD="$PFX-replay"

# The newest save a run left that is not the one it loaded, the backup, or the gallery.
newest_save() {   # <run dir> <file to exclude>
    local f
    for f in $(ls -t "$1"/save/*.sav 2>/dev/null); do
        cmp -s "$f" "$2" && continue
        echo "$f"; return 0
    done
    return 1
}

[ "$STREAM" = "-" ] && unset INCURSION_MAP_STREAM || export INCURSION_MAP_STREAM="$STREAM"
tools/build_fixture.sh "$CHAR" "$PFX-out" > "$PFX-build.log" 2>&1 \
    || { echo "char_arrive: $(grep -m1 'BUILD FAILED' "$PFX-build.log" || tail -1 "$PFX-build.log")" >&2; exit 2; }
unset INCURSION_MAP_STREAM
cp "$PFX-out/$(basename "$CHAR" .char).sav" "$LOAD" || exit 2
SAV="$LOAD"
if [ "$SKIP" != "-" ]; then
    [ -n "$KEYS" ] && [ -n "$SEED" ] && [ "$TICK" != "-" ] || { echo "char_arrive: the arrival needs the key script, seed and tick" >&2; exit 2; }
    rm -rf "$RD"
    INCURSION_LOAD="$LOAD" INCURSION_KEYS_SKIP="$SKIP" INCURSION_SEED_TICK="$TICK" INCURSION_OPTIONS="$OPTS" INCURSION_RUN_DIR="$RD" \
        tools/headless.sh "$KEYS" "$SEED" > "$PFX-replay.log" 2>&1 < /dev/null
    rc=$?
    # 6: the key script ran out before the game ended. The replay saved before that, or the run left no
    # save and stops below; a skip that is off by one lands here and must show as a difference, not a crash.
    { [ "$rc" -eq 0 ] || [ "$rc" -eq 6 ]; } || { echo "char_arrive: the arrival replay of $CHAR ended with exit $rc (see $PFX-replay.log)" >&2; exit 2; }
    SAV="$(newest_save "$RD" "$LOAD")" || { echo "char_arrive: the arrival replay of $CHAR saved nothing (see $PFX-replay.log)" >&2; exit 2; }
fi
INCURSION_OPTIONS="$OPTS" tools/char_dump.sh "$SAV" "$PFX.canon" > /dev/null 2>&1 \
    || { echo "char_arrive: cannot dump the arrival of $CHAR" >&2; exit 2; }
exit 0
