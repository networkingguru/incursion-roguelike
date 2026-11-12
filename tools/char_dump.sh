#!/bin/bash
# Print the canonical dump of a saved character: every rID as a resource name,
# no handle, no pointer, no wall-clock value, and the fields the default -dump
# leaves out (per-level hit and mana rolls, skill ranks and pools, the perk
# block, the kit with qualities, spell lists, stati). Two dumps of one
# character, from two loads or two builds, are comparable byte for byte.
#
# Usage: INCURSION_OPTIONS=<settings file> tools/char_dump.sh <save-or-fixture> [out]
#        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
#            tools/char_dump.sh lizardfolk-monk-seed1
#        INCURSION_OPTIONS=... tools/char_dump.sh save/Jaoin.sav /tmp/jaoin.canon
#
# A bare name (no '/', no ".sav") means tools/fixtures/chars/<name>.sav. Output
# goes to stdout, or to [out] when given; on failure [out] is not written.
#
# INCURSION_OPTIONS is mandatory, as for tools/headless.sh, so a run always
# names its settings. -dump itself reads no settings: the variable is checked
# and echoed to stderr, and nothing else uses it.
#
# SANDBOX. The dump runs through tools/dump_save.sh, the sandbox wrapper made
# for -dump: it gives the binary a disposable INCURSIONPATH with mod/ and lib/
# linked in, and fails the run if the binary wrote any file. tools/headless.sh
# plays a key script and cannot print a dump, so it is not the wrapper here.
# Never run the binary directly. The canonical mode is the environment
# variable INCURSION_DUMP_CANONICAL=1 read by src/Dump.cpp (RunSaveDump); this
# script sets it. INCURSION_BIN picks another build, as for dump_save.sh.
#
# Exit: 0 printed; 2 bad usage or a missing input; any other code is the
#       binary's, from dump_save.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ARG="${1:-}"
OUT="${2:-}"
if [ -z "$ARG" ]; then
    echo "usage: INCURSION_OPTIONS=<settings file> tools/char_dump.sh <save-or-fixture> [out]" >&2
    exit 2
fi
if [ -z "${INCURSION_OPTIONS:-}" ]; then
    echo "INCURSION_OPTIONS is required; choose a settings file from tools/fixtures/" >&2
    exit 2
fi
if [ ! -f "$INCURSION_OPTIONS" ]; then
    echo "INCURSION_OPTIONS names a file that is not there: $INCURSION_OPTIONS" >&2
    exit 2
fi
echo "opts:  $INCURSION_OPTIONS" >&2

case "$ARG" in
    */*|*.sav) SAVE="$ARG" ;;
    *)         SAVE="tools/fixtures/chars/$ARG.sav"
               [ -f "$SAVE" ] || SAVE="tools/fixtures/specimens/$ARG.sav" ;;
esac
if [ ! -f "$SAVE" ]; then
    echo "no such save or fixture: $ARG (looked for $SAVE)" >&2
    exit 2
fi

if [ -n "$OUT" ]; then
    TMP="$(mktemp "${OUT}.XXXXXX")" || exit 2
    INCURSION_DUMP_CANONICAL=1 tools/dump_save.sh "$SAVE" > "$TMP"
    STATUS=$?
    if [ "$STATUS" -eq 0 ]; then
        mv -f "$TMP" "$OUT"
    else
        rm -f "$TMP"
    fi
    exit $STATUS
fi

INCURSION_DUMP_CANONICAL=1 tools/dump_save.sh "$SAVE"
