#!/bin/bash
# Freeze one generated character into tools/fixtures/chars/, or regenerate one.
#
# Usage: tools/make_char_fixture.sh <name> <keyscript> <seed> <options> [--force]
#
#   tools/make_char_fixture.sh lizardfolk-monk-seed1 \
#       tools/keys/lizardfolk-monk-save.keys 1 \
#       tools/fixtures/options-2026-08-22.dat
#
# WHY A CHARACTER MUST BE FROZEN AT ALL. A character built by a key script is
# not reproducible across module changes. An rID in this engine is a POSITION,
# so one resource added to lib/ shifts every id above it and silently rewrites
# every seed-pinned character in the check suite. Measured 2026-09-12: commit
# bef32c3 added one Effect to lib/m_items.irh, and the seed-1 Lizardfolk monk
# went from STR 18 holding a long sword +3 to STR 14 holding a quarterstaff, on
# byte-identical attribute dice. A character LOADED from a save does not move,
# because the v1 save schema converts every saved rID through that save's own
# per-module manifest (v1ConvertManifestRid, src/SaveV1.cpp): same save, module
# with one Effect appended, byte-identical character. So a check that wants a
# stable character must load one, and this script is what makes one to load.
# See bd inc-1fjk.
#
# A FIXTURE IS THREE FILES, because a .sav on its own is an opaque blob that
# nobody can audit and nobody dares regenerate:
#
#   <name>.sav        the frozen save. This is the fixture.
#   <name>.keys       the key script that generated it, copied in. Without it
#                     the .sav cannot be remade, and a save format will one day
#                     make remaking every fixture compulsory.
#   <name>.sheet.txt  the character, in the engine's own words, so a reader can
#                     see what is in the .sav without loading it.
#
# WHERE THE PROVENANCE LIVES, AND WHY. Inside <name>.sheet.txt, as a header
# block above the character. Three reasons. It keeps the file count at three,
# so there is no fourth file to forget on a regeneration. The sheet is the file
# a person actually opens -- the .sav is unreadable and the .keys is the input,
# not the output -- so the provenance is on the page they are already reading.
# And this script rewrites the whole sheet on every regeneration, header and
# body together, so the header cannot drift out of step with the .sav beside
# it the way a separate ledger row silently would.
#
# THE SHEET IS DUMPED FROM THE FINISHED FIXTURE, NOT FROM THE GENERATING RUN.
# This script generates the character, copies the .sav into place, and then
# LOADS that copy back through tools/headless.sh to write the sheet. It costs a
# second session and buys the one guarantee that matters: no fixture is ever
# published without having been loaded once, so a .sav that cannot be read back
# fails here rather than in somebody else's check a month later. The same run
# also asserts that the fixture file is byte-identical afterwards, which is the
# sandbox claim tools/headless.sh makes about INCURSION_LOAD.
#
# REGENERATION IS THE POINT OF --force, not an escape hatch. Without it this
# script refuses to touch an existing fixture, because overwriting one silently
# retires every check built on it. With it, the command in the sheet header
# reproduces the fixture; that line is written so that a save-format change
# years from now is a matter of running what the file already says.
#
# REGENERATING PRODUCES A DIFFERENT FILE, AND THAT IS NOT A DIFFERENT
# CHARACTER. Measured 2026-09-12: the same name, key script, seed, settings and
# binary, run twice, gave sha256 2b5fb59c... and then 603f109b..., while
# tools/check_char_fixture.sh passed on both -- same name, race, class and
# Strength. A .sav carries clocks and counters that a second run cannot repeat.
# So a regeneration is always a real diff in git, and the question to ask of
# that diff is what the sheet says, never what the bytes say.
#
# Exit: 0 the fixture is written, 2 anything else. Nothing partial is left
#       behind: the copies happen after the generating session has been judged.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

DEST="tools/fixtures/chars"
LOAD_KEYS="tools/keys/load-char-sheet.keys"

FORCE=0
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--force" ]; then
        FORCE=1
    else
        ARGS+=("$arg")
    fi
done
set -- ${ARGS[@]+"${ARGS[@]}"}

NAME="${1:-}"
KEYS="${2:-}"
SEED="${3:-}"
OPTIONS="${4:-}"

usage() {
    echo "usage: tools/make_char_fixture.sh <name> <keyscript> <seed> <options> [--force]"
    echo "  name      what the fixture is called: $DEST/<name>.sav and its two companions"
    echo "  keyscript the script that builds the character AND SAVES HIM. It must end"
    echo "            with the System Menu's [b] Save and Continue -- ESC b -- because"
    echo "            that is the only save the game offers that does not end the"
    echo "            session. tools/keys/lizardfolk-monk-save.keys is the worked example."
    echo "  seed      the seed to generate under. Not optional: an unseeded run rolls"
    echo "            different attributes, so it would freeze a different character."
    echo "  options   a settings file from tools/fixtures/. Settings change what a"
    echo "            seeded session does, so the fixture is only meaningful with the"
    echo "            one that made it, and that name goes into the sheet header."
    exit 2
}

[ -n "$NAME" ] && [ -n "$KEYS" ] && [ -n "$SEED" ] && [ -n "$OPTIONS" ] || usage

# The name becomes a file name AND a command-line argument to the game, because
# tools/headless.sh passes the save's base name to -load. Anything with a '/'
# in it would also change how Game::LoadNamedGame resolves the file
# (src/Registry.cpp:1322-1332), so the character set is narrow on purpose.
case "$NAME" in
    *[!A-Za-z0-9._-]*|""|-*|.*)
        echo "make_char_fixture: '$NAME' is not a usable fixture name."
        echo "Use letters, digits, dot, dash and underscore, starting with a letter"
        echo "or a digit. The name becomes a file name and a -load argument."
        exit 2 ;;
esac
case "$SEED" in
    ""|*[!0-9]*) echo "make_char_fixture: the seed must be a whole number, not '$SEED'"; exit 2 ;;
esac
[ -f "$KEYS" ] || { echo "make_char_fixture: no such key script: $KEYS"; exit 2; }
[ -f "$OPTIONS" ] || { echo "make_char_fixture: no such settings file: $OPTIONS"; exit 2; }
[ -f "$LOAD_KEYS" ] || { echo "make_char_fixture: $LOAD_KEYS is missing; it reads the fixture back"; exit 2; }
[ -x ./incursion-headless ] || {
    echo "make_char_fixture: ./incursion-headless not built."
    echo "Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

SAV="$DEST/$NAME.sav"
SHEET="$DEST/$NAME.sheet.txt"
COPIED_KEYS="$DEST/$NAME.keys"

if [ "$FORCE" -eq 0 ]; then
    for f in "$SAV" "$COPIED_KEYS" "$SHEET"; do
        [ -e "$f" ] || continue
        echo "make_char_fixture: $f already exists, and a fixture is frozen."
        echo "Every check built on it would quietly start measuring a different"
        echo "character. To replace it on purpose, add --force:"
        echo "  tools/make_char_fixture.sh $NAME $KEYS $SEED $OPTIONS --force"
        exit 2
    done
fi

mkdir -p "$DEST" || exit 2

# ---------------------------------------------------------------------------
# 1. Generate. The session runs in its own sandbox under logs/runs/, so this
#    cannot touch the owner's real save/ even if the key script drifts.
echo "--- generating $NAME (seed $SEED, $(basename "$OPTIONS")) ---"
OUT="$(INCURSION_OPTIONS="$OPTIONS" tools/headless.sh "$KEYS" "$SEED" 2>&1 </dev/null)"
STATUS=$?
RUN="$(printf '%s\n' "$OUT" | awk '/^run:/ {print $2}')"
printf '%s\n' "$OUT" | sed 's/^/  | /'

# 0 is a script that finished, 3 is a key budget that ran out. Every other code
# says the session did not play the game it was asked to play, and freezing a
# character out of one would freeze whatever wreckage it reached. The codes are
# listed in tools/headless.sh's own header.
if [ "$STATUS" -ne 0 ] && [ "$STATUS" -ne 3 ]; then
    echo "make_char_fixture: the generating session ended badly (exit $STATUS)."
    echo "Nothing was written. The session is in ${RUN:-logs/runs}."
    exit 2
fi

SAVES=()
for f in "$RUN"/save/*.sav; do
    [ -f "$f" ] && SAVES+=("$f")
done

if [ "${#SAVES[@]}" -eq 0 ]; then
    echo "make_char_fixture: the session wrote no .sav, so there is nothing to freeze."
    echo "The key script must END BY SAVING. ESC b is the System Menu's [b] Save"
    echo "and Continue (src/Player.cpp:843) and is the only save that does not"
    echo "also end the session; see tools/keys/lizardfolk-monk-save.keys. Give the"
    echo "game a turn or two after the keypress -- the file is written when that"
    echo "turn resolves, not by the keypress itself."
    echo "The session is in $RUN."
    exit 2
fi
if [ "${#SAVES[@]}" -gt 1 ]; then
    echo "make_char_fixture: the session wrote ${#SAVES[@]} save files, so which one"
    echo "is the fixture is a guess. Make the key script save exactly once."
    printf '  %s\n' "${SAVES[@]}"
    exit 2
fi
GENERATED="${SAVES[0]}"
# A .backup means Game::SaveGame ran a second time and renamed the first file
# (src/Registry.cpp:1141-1170). The fixture is still the .sav -- the later save
# -- but the key script is then saving at a moment it does not name, which is
# worth knowing before somebody tries to explain the fixture's contents.
if [ -f "$GENERATED.backup" ]; then
    echo "note: $(basename "$GENERATED").backup exists, so the session saved more than"
    echo "      once. The fixture is the LAST save. Check the key script says so."
fi

# ---------------------------------------------------------------------------
# 2. Put the .sav and the .keys in place. The sheet needs the fixture to exist
#    first, because it is dumped by loading the fixture rather than the
#    session's own copy -- see the header.
cp -f "$GENERATED" "$SAV" || exit 2
chmod u+w "$SAV"
cp -f "$KEYS" "$COPIED_KEYS" || exit 2

SAV_SHA="$(shasum -a 256 "$SAV" | awk '{print $1}')"
MOD_SHA="unknown"
[ -f mod/Incursion.Mod ] && MOD_SHA="$(shasum -a 256 mod/Incursion.Mod | awk '{print $1}')"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
DIRTY=""
if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
    DIRTY="the working tree was dirty, so this fixture may hold changes that commit does not"
fi

# ---------------------------------------------------------------------------
# 3. Read the fixture back. This both writes the sheet and proves the .sav
#    loads, and it is done through tools/headless.sh so the sandbox rule is
#    exercised rather than asserted.
echo
echo "--- reading $SAV back ---"
BEFORE="$SAV_SHA"
OUT="$(INCURSION_CHAR_PROBE=1 INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$SAV" \
       tools/headless.sh "$LOAD_KEYS" "$SEED" 2>&1 </dev/null)"
STATUS=$?
LOADRUN="$(printf '%s\n' "$OUT" | awk '/^run:/ {print $2}')"
printf '%s\n' "$OUT" | sed 's/^/  | /'

if [ "$STATUS" -ne 0 ] && [ "$STATUS" -ne 3 ]; then
    echo "make_char_fixture: the fixture was written but WILL NOT LOAD (exit $STATUS)."
    echo "The three files are in $DEST and the failing session is in ${LOADRUN:-logs/runs}."
    exit 2
fi

AFTER="$(shasum -a 256 "$SAV" | awk '{print $1}')"
if [ "$BEFORE" != "$AFTER" ]; then
    echo "make_char_fixture: THE RUN THAT LOADED THE FIXTURE CHANGED IT."
    echo "A loaded session writes back to its own save file, so the fixture must be"
    echo "copied into the run's sandbox and never played in place. That is what"
    echo "INCURSION_LOAD does in tools/headless.sh; something has undone it, and"
    echo "$SAV is no longer the file this run generated."
    exit 2
fi

PROBE="$LOADRUN/logs/charprobe.txt"
if [ ! -f "$PROBE" ]; then
    echo "make_char_fixture: no $PROBE, so there is no character sheet to keep."
    echo "INCURSION_CHAR_PROBE=1 makes Game::SaveGame write it, so this means the"
    echo "loading key script $LOAD_KEYS did not reach its save."
    exit 2
fi

# ---------------------------------------------------------------------------
# 4. Write the sheet: provenance first, then the character.
{
    echo "=== fixture: $NAME ==="
    echo
    echo "This file is the audit record for"
    echo "  $SAV"
    echo "and tools/make_char_fixture.sh writes the whole of it. Do not edit it"
    echo "by hand: it would then describe a character the .sav beside it does"
    echo "not hold, and that is the one failure tools/check_char_fixture.sh"
    echo "exists to catch."
    echo
    echo "made on          $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "made at commit   $COMMIT"
    [ -n "$DIRTY" ] && echo "                 $DIRTY"
    echo "seed             $SEED"
    echo "settings         $OPTIONS"
    echo "key script       $KEYS"
    echo "                 copied to $COPIED_KEYS"
    echo "saved in game as $(basename "$GENERATED")"
    echo "sha256 .sav      $SAV_SHA"
    echo "sha256 module    $MOD_SHA"
    echo "                 mod/Incursion.Mod is what the save's rID manifest"
    echo "                 was written against. A fixture that stops loading"
    echo "                 is worth comparing against the module that made it."
    echo
    echo "regenerate with"
    echo "  tools/make_char_fixture.sh $NAME $KEYS $SEED $OPTIONS --force"
    echo "Regenerating gives a BYTE-DIFFERENT .sav holding the SAME character:"
    echo "a save carries clocks and counters no second run repeats. Judge a"
    echo "regeneration by this sheet, never by the size of the diff."
    echo
    echo "The character below is the engine's own dump. It was taken by LOADING"
    echo "the .sav beside this file and saving it again under"
    echo "INCURSION_CHAR_PROBE=1 (Game::SaveGame, src/Registry.cpp:1105-1111)."
    echo "A few of its lines belong to that reading session and not to the"
    echo "character: the torch's remaining turns, the Level Statistics table"
    echo "and the Messages at the end all move by the turns"
    echo "$LOAD_KEYS spends. Everything above Inventory is the"
    echo "character. For the resource ids behind the item names, which are what"
    echo "a module change moves, run:"
    echo "  tools/dump_save.sh $SAV"
    echo
    echo "=== the character, as the engine writes him ==="
    echo
    cat "$PROBE"
} > "$SHEET" || exit 2

echo
echo "wrote $SAV"
echo "      $COPIED_KEYS"
echo "      $SHEET"
echo
echo "The fixture generated, loaded back, and came through the load unchanged."
echo "Prove it keeps working:  tools/check_char_fixture.sh"
exit 0
