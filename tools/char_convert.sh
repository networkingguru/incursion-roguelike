#!/usr/bin/env bash
# Convert one old `.sav` fixture to a `.char` file (bead inc-10v7f, spec
# section 8): record a skeleton with the current binary, then set every value
# that differs from the old fixture to the old value, then build, and demand
# that the dump of the build equals the dump of the old `.sav`.
#
# ponytail: this helper (with tools/char_convert_map.py, which holds the one
# mapping table) stays only until the epic conversion lands (inc-pu6v.369).
# The ceiling: the tables map the decisions a dump states (scalars, perks, the
# feat queue, skill ranks, the kit, two item quantities). A difference in a
# RESULT (abilities, derived attributes, the equipment arrangement) is a rule
# that changed since the old save was made: the conversion fails on it, by
# design, and prints it. Extend the tables in the bead that needs more.
#
# Usage: tools/char_convert.sh <fixture-name> <out.char> [--withhold <key>]
#        INCURSION_BIN=<binary>              the binary (default ./incursion-headless)
#        CHAR_CONVERT_LOGS=<dir>             specimens (default logs/char-convert)
#        CHAR_CONVERT_MANIFEST=<file>        the MANIFEST (default tools/fixtures/chars/MANIFEST)
#        CHAR_CONVERT_DIR=<dir>              where <name>.sav lives (default tools/fixtures/chars)
#
# STEPS (the spec's, numbered as in the bead):
#   1. Read the fixture's MANIFEST row (name, key script, seed, settings file).
#      Walk the key script under tools/headless.sh with INCURSION_RECORD_CHAR
#      set: the recorded file is the skeleton. The old .sav is never handed to
#      the walk or to a build; only tools/dump_save.sh reads it, from a copy in
#      its own sandbox, and this script proves it stayed byte-identical.
#   1b. The settings come from the old .sav, not from the MANIFEST: the
#      Options line of its dump picks the one tools/fixtures/options-*.dat
#      whose options equal it (tools/char_convert_map.py options). If the pick
#      is not the MANIFEST's file, the walk runs again under the pick. None
#      matches: fail, naming the differing options. The pick is used for the
#      walk, the build, both dumps, and is the `options:` line of the output.
#   2. Dump the old .sav (tools/char_dump.sh).
#   3. Build the skeleton, play the old script's post-creation steps on it,
#      dump the result, compare with tools/canon_compare.py. See THE ARRIVAL.
#   4. Set each mapped value that differs, from the tables in char_convert_map.py.
#   5. Build again and compare. Exit 0 only when the dumps match outside the one
#      allowlist of tools/canon_compare.py. A differing line with no mapping
#      fails and is printed. Nothing is added to the allowlist.
#   6. --withhold <key>: skip setting that one key in step 4, to prove step 5.
#
# THE ARRIVAL (phase 11e). An old .sav was written by its key script AFTER
# creation ended: the game loop began on level 1, turns passed, then the script
# saved. A built character is dumped at the end of creation, before any turn,
# so the two differ in gold picked up, stati of the first turn, hunger and
# the like, and not in any rule. So each built character is loaded, the part of
# the key script that ran after creation is played on it (tools/headless.sh with
# INCURSION_LOAD and INCURSION_KEYS_SKIP), it saves as the script saves, and
# THAT save is dumped. The split point comes from the game: Game::NewGameTail
# writes the number of script entries creation consumed beside the walk save
# (<skeleton>.walk.keypos), and the tick of the seed series the gameplay stream
# starts from (<skeleton>.walk.tick, set back with INCURSION_SEED_TICK), so the
# replay plays its first turn on the walk's random stream. A script the game cannot split fails with the
# game's reason; no script is cut by hand. Before the replay is trusted, step 3
# proves it on today's code alone: the replay of the skeleton MUST dump equal to
# the final save of the walk that recorded the skeleton (proof.txt); a
# difference there is a defect in the method and stops the run (exit 2).
#
# THE UNSEEN ROLLS (phase 11g). A decision whose value a dump shows only
# through its result (a script's draw, an effect's damage roll) is found by
# search: the walk writes, beside the skeleton, <skeleton>.rolls with the range
# of each such roll (the UNSEEN column of CREATION_KEY_LIST), and
# tools/char_roll_search.py builds, replays, dumps and compares every
# combination (at most 500; a larger space is reported, not sampled). The
# lowest matching combination is kept and the other matches are listed. When
# nothing matches, fewer than two combinations completed, or a build added an
# unseen key's line with a default, the walk's values stay as recorded and each
# searched key is named UNRESOLVED in unset.txt and the header.
#
# THE MAP (phase 11h). The map is made at the end of creation, from wherever the
# random streams stand, and the build reaches that point by other draws than the
# walk. The walk writes beside its save (<skeleton>.walk.stream) the stream
# position it stood at before it made the map (the tick of the seed series, the
# seed and the draw count of the gameplay stream); every build stands there
# first (INCURSION_MAP_STREAM, kept by tools/build_fixture.sh), so it makes the
# walk's map. The method proof therefore also compares the Location section
# (Position, Map) of the replay with the walk's final save.
#
# Specimens in <logs>/<name>/: skeleton.char, skeleton.rolls, skeleton.walk.keypos,
# skeleton.walk.stream, old.canon, walk.canon (the walk at creation), walkfinal.canon
# (its final save), proof.txt, proof-location.txt, built0.canon, built.canon (after the replay), built0-replay/,
# built-replay/, diff0.txt, diff.txt, settings.txt, values-set.txt, unset.txt,
# roll-search.txt, walk/, build logs.
# <out.char> is written whenever the comparison completed (exit 0 or 1), with a
# header that names the fixture, the old .sav, the binary commit, the RESULT,
# the arrival (key script, seed, skip, tick, map stream: the input of tools/char_attribute.sh),
# the searched rolls (`# rolls:` lines, the same),
# each value set from the old dump, and each value left unset.
# Exit: 0 converted; 1 the dumps differ (lines printed; <out.char> still written);
# 2 could not run (no <out.char>).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

NAME="${1:-}"; OUTCHAR="${2:-}"; WITHHOLD=""
if [ "${3:-}" = "--withhold" ]; then WITHHOLD="${4:-}"; [ -n "$WITHHOLD" ] || NAME=""; fi
if [ -z "$NAME" ] || [ -z "$OUTCHAR" ]; then
    echo "usage: tools/char_convert.sh <fixture-name> <out.char> [--withhold <key>]" >&2
    exit 2
fi
BIN="${INCURSION_BIN:-./incursion-headless}"
LOGS="${CHAR_CONVERT_LOGS:-logs/char-convert}"
MANIFEST="${CHAR_CONVERT_MANIFEST:-tools/fixtures/chars/MANIFEST}"
FDIR="${CHAR_CONVERT_DIR:-tools/fixtures/chars}"
[ -x "$BIN" ] || { echo "$BIN not built. Run: BACKEND=posix ./build_macos.sh" >&2; exit 2; }
export INCURSION_BIN="$BIN"

ROW="$(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" | awk -v n="$NAME" '$1 == n { print; exit }')"
[ -n "$ROW" ] || { echo "char_convert: no MANIFEST row for $NAME in $MANIFEST" >&2; exit 2; }
set -- $ROW
KEYS="$2"; SEED="$3"; OPTS="$4"
SAV="$FDIR/$NAME.sav"
[ -f "$SAV" ] || { echo "char_convert: no such save: $SAV" >&2; exit 2; }
[ -f "$KEYS" ] && [ -f "$OPTS" ] || { echo "char_convert: key script or settings file missing ($KEYS, $OPTS)" >&2; exit 2; }

OD="$LOGS/$NAME"
rm -rf "$OD"; mkdir -p "$OD" || exit 2
SUM_BEFORE="$(cksum < "$SAV")"

# 1. The skeleton, walked under the MANIFEST's settings first.
walk() {   # walk <settings file> <tag>: records $OD/skeleton.char and its walk save
    rm -f "$OD/skeleton.char" "$OD/skeleton.rolls" "$OD/skeleton.walk.sav" "$OD/skeleton.walk.keypos" "$OD/skeleton.walk.tick" "$OD/skeleton.walk.stream"
    INCURSION_RECORD_CHAR="$ROOT/$OD/skeleton.char" INCURSION_OPTIONS="$1" \
        INCURSION_RUN_DIR="$ROOT/$OD/walk$2" tools/headless.sh "$KEYS" "$SEED" > "$OD/walk$2.log" 2>&1 < /dev/null
    [ -f "$OD/skeleton.char" ] || { echo "char_convert: the walk of $KEYS recorded no .char (see $OD/walk$2.log)" >&2; exit 2; }
}
walk "$OPTS" ""

# 2. The oracle.
INCURSION_OPTIONS="$OPTS" tools/char_dump.sh "$SAV" "$OD/old.canon" > /dev/null 2>&1 \
    || { echo "char_convert: cannot dump $SAV" >&2; exit 2; }

# 1b. The settings the old .sav was made under.
[ -f "$OD/skeleton.walk.sav" ] || { echo "char_convert: the walk left no walk save" >&2; exit 2; }
INCURSION_OPTIONS="$OPTS" tools/char_dump.sh "$OD/skeleton.walk.sav" "$OD/walk.canon" > /dev/null 2>&1 \
    || { echo "char_convert: cannot dump the walk save" >&2; exit 2; }
MANIFEST_OPTS="$OPTS"
CHOSEN="$(tools/char_convert_map.py options "$OD/old.canon" "$OD/walk.canon" "$MANIFEST_OPTS" tools/fixtures 2> "$OD/options.err")"
RCO=$?
if [ "$RCO" -ne 0 ] || [ -z "$CHOSEN" ]; then   # no settings file fits, or the tool stopped: the reason is on stdout or stderr
    echo "char_convert: $NAME: cannot choose the settings (exit $RCO): $(head -3 "$OD/options.err" | tr '\n' ' ')${CHOSEN}" >&2
    exit 2
fi
if [ "$CHOSEN" != "$MANIFEST_OPTS" ]; then
    echo "char_convert: settings: $CHOSEN (the MANIFEST names $MANIFEST_OPTS)"
    OPTS="$CHOSEN"
    mv "$OD/walk" "$OD/walk-manifest-settings"
    walk "$OPTS" ""
else
    echo "char_convert: settings: $OPTS (the MANIFEST's file)"
fi
echo "$OPTS (MANIFEST: $MANIFEST_OPTS)" > "$OD/settings.txt"

# The number of script entries creation consumed, or the game's reason it cannot say.
KEYPOS="$(cat "$OD/skeleton.walk.keypos" 2>/dev/null)"
case "$KEYPOS" in
    ''|*[!0-9]*)
        echo "char_convert: $NAME: cannot split the key script into creation and arrival: ${KEYPOS:-the walk wrote no skeleton.walk.keypos}" >&2
        exit 1 ;;
esac
TICK="$(cat "$OD/skeleton.walk.tick" 2>/dev/null)"
case "$TICK" in
    ''|*[!0-9]*) echo "char_convert: $NAME: the walk wrote no seed tick (skeleton.walk.tick)" >&2; exit 2 ;;
esac
STREAM="$(cat "$OD/skeleton.walk.stream" 2>/dev/null)"
case "$STREAM" in
    [0-9]*:[0-9]*:[0-9]*) ;;
    *) echo "char_convert: $NAME: the walk wrote no map stream position (skeleton.walk.stream)" >&2; exit 2 ;;
esac
echo "char_convert: creation consumed $KEYPOS script entries of $KEYS; the rest is replayed on the build"

# The newest save a run left that is not the one it loaded, the backup, or the gallery.
newest_save() {   # <run dir> [<file to exclude>]
    local f
    for f in $(ls -t "$1"/save/*.sav 2>/dev/null); do
        [ -n "${2:-}" ] && cmp -s "$f" "$2" && continue
        echo "$f"; return 0
    done
    return 1
}

# build, load, replay the arrival, dump: the one tool tools/char_attribute.sh also calls.
ARRIVE="${CHAR_ARRIVE_TOOL:-tools/char_arrive.sh}"
build_dump() {   # build_dump <char> <tag>: writes $OD/<tag>.canon; exit 2 on failure
    "$ARRIVE" "$1" "$OD/$2" "$KEYS" "$SEED" "$OPTS" "$KEYPOS" "$TICK" "$STREAM" 2> "$OD/$2-arrive.err" \
        || { cat "$OD/$2-arrive.err" >&2; exit 2; }
}

# 3. Build the skeleton, play the arrival, prove the method, compare.
build_dump "$OD/skeleton.char" built0 || exit 2
WSAV="$(newest_save "$OD/walk")" || { echo "char_convert: the walk left no final save" >&2; exit 2; }
INCURSION_OPTIONS="$OPTS" tools/char_dump.sh "$WSAV" "$OD/walkfinal.canon" > /dev/null 2>&1 \
    || { echo "char_convert: cannot dump the walk's final save" >&2; exit 2; }
tools/canon_compare.py --all "$OD/built0.canon" "$OD/walkfinal.canon" > "$OD/proof.txt" 2>&1
RCP=$?
# The proof also compares the Location section (Position, Map): the replay and the walk are the same game,
# so both stand on one map at one place. The comparison of the build with the OLD dump keeps dropping it.
location() { awk '/^=== /{ p = ($0 ~ /^=== Location ===/) } p' "$1"; }
diff -u <(location "$OD/built0.canon") <(location "$OD/walkfinal.canon") > "$OD/proof-location.txt" 2>&1
RCL=$?
if [ "$RCL" -ne 0 ]; then RCP=1; cat "$OD/proof-location.txt" >> "$OD/proof.txt"; fi
if [ "$RCP" -ne 0 ]; then
    echo "char_convert: METHOD DEFECT: build + load + arrival replay of the skeleton does not equal the walk's own final save; these lines differ (not covered by the allowlist):" >&2
    grep -E '^[-+][^-+]' "$OD/proof.txt" | cut -c1-170 | head -40 >&2
    echo "(full diff: $OD/proof.txt)" >&2
    exit 2
fi
echo "char_convert: method proof: the replay of the skeleton equals the walk's final save, Position and Map included"
tools/canon_compare.py --all "$OD/built0.canon" "$OD/old.canon" > "$OD/diff0.txt" 2>&1
RC0=$?
[ "$RC0" -le 1 ] || { echo "char_convert: canon_compare failed (exit $RC0)" >&2; exit 2; }

# 4. Set the mapped values.
MAPARGS=()
[ -n "$WITHHOLD" ] && MAPARGS=(--withhold "$WITHHOLD")
tools/char_convert_map.py convert "$OD/old.canon" "$OD/built0.canon" "$OD/skeleton.char" "$OD/converted.char" \
    ${MAPARGS[@]+"${MAPARGS[@]}"} --report "$OD/values-set.txt" --unset "$OD/unset.txt" --rolls "$OD/skeleton.rolls" > "$OD/map.log" 2>&1 \
    || { echo "char_convert: the mapping failed:" >&2; cat "$OD/map.log" >&2; exit 2; }
NSET="$(grep -c '' "$OD/values-set.txt")"
KINDS="$(cut -d: -f1 "$OD/values-set.txt" | sort | uniq -c | awk '{printf "%s%s %s", (NR>1 ? ", " : ""), $2, $1}')"
[ -n "$KINDS" ] || KINDS="none"

# 4b. The unseen rolls: search every combination (see THE UNSEEN ROLLS).
FINAL="$OD/converted.char"
SEARCH="none: the walk recorded no roll the dump shows only through its result"
if [ -s "$OD/skeleton.rolls" ]; then
    SEARCH="$(tools/char_roll_search.py "$OD/skeleton.char" "$OD/skeleton.rolls" "$OD/old.canon" "$OD/roll-search" "$KEYS" "$SEED" "$OPTS" "$KEYPOS" "$TICK" "$STREAM" 2> "$OD/roll-search.err")"
    RCS=$?
    case "$RCS" in
        0) FINAL="$OD/roll-search.char"   # a combination matched: its values are facts
           cp "$OD/roll-search-values.txt" "$OD/values-set.txt"; cp "$OD/roll-search-unset.txt" "$OD/unset.txt"
           NSET="$(grep -c '' "$OD/values-set.txt")"
           KINDS="$(cut -d: -f1 "$OD/values-set.txt" | sort | uniq -c | awk '{printf "%s%s %s", (NR>1 ? ", " : ""), $2, $1}')"
           [ -n "$KINDS" ] || KINDS="none"
           echo "char_convert: roll search: $SEARCH" ;;
        1|3|5) # no match, too large, or not searched: the walk's values stay and each searched key is named unresolved
           cat "$OD/roll-search-unresolved.txt" >> "$OD/unset.txt"
           echo "char_convert: roll search: $SEARCH" ;;
        4) ;;
        *) echo "char_convert: the roll search failed: $SEARCH $(cat "$OD/roll-search.err")" >&2; exit 2 ;;
    esac
fi

# 5. Build again, compare.
build_dump "$FINAL" built || exit 2
tools/canon_compare.py --all "$OD/built.canon" "$OD/old.canon" > "$OD/diff.txt" 2>&1
RC=$?
[ "$RC" -le 1 ] || { echo "char_convert: canon_compare failed (exit $RC)" >&2; exit 2; }
SUM_AFTER="$(cksum < "$SAV")"
[ "$SUM_BEFORE" = "$SUM_AFTER" ] || { echo "char_convert: THE OLD .sav CHANGED during the run: $SAV" >&2; exit 2; }
NDIFF="$(grep -cE '^[-+][^-+]' "$OD/diff.txt")"

# The .char is written whenever the comparison completed, with its result: a
# fixture that still differs needs tools/char_attribute.sh, and that takes this file.
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
[ -n "$(git status --porcelain -- src inc lib tools 2>/dev/null)" ] && COMMIT="$COMMIT+uncommitted"
if [ "$RC" -eq 0 ]; then RESULT="CONVERTED: the dump of the build equals the dump of the old .sav outside the allowlist of tools/canon_compare.py"
else RESULT="DIFFERS: $NDIFF dump line(s) of the build differ from the old .sav (the full diff is the comparison of the dumps; tools/char_attribute.sh takes this file)"; fi
{
    echo "# $NAME: converted from $SAV by tools/char_convert.sh."
    echo "# Skeleton: key script $KEYS, seed $SEED, settings $OPTS, recorded by binary commit $COMMIT."
    echo "# result: $RESULT"
    echo "# arrival: $KEYS $SEED $KEYPOS $TICK $STREAM"
    echo "# roll search: $SEARCH"
    [ -s "$OD/skeleton.rolls" ] && awk -F'\t' '{ printf "# rolls: %s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5 }' "$OD/skeleton.rolls"
    if [ "$NSET" -eq 0 ]; then
        echo "# Values set from the old dump: none (the skeleton already matched)."
    else
        echo "# Values set from the old dump ($NSET), skeleton value -> old value:"
        sed 's/^/#   /' "$OD/values-set.txt"
    fi
    if [ -s "$OD/unset.txt" ]; then
        echo "# Values NOT set from the old dump (the dump shows each only through a result):"
        sed 's/^/#   /' "$OD/unset.txt"
    fi
    cat "$FINAL"
} > "$OUTCHAR"
if [ -s "$OD/unset.txt" ]; then
    echo "char_convert: values not set from the old dump (the dump shows only a result):"
    sed 's/^/char_convert:   /' "$OD/unset.txt"
fi
if [ "$RC" -ne 0 ]; then
    echo "char_convert: $NAME does NOT convert; $NSET value(s) set ($KINDS); $NDIFF dump lines differ and have no mapping or still differ:"
    grep -E '^[-+][^-+]' "$OD/diff.txt" | cut -c1-170 | head -40
    echo "(full diff: $OD/diff.txt; wrote $OUTCHAR for tools/char_attribute.sh)"
    exit 1
fi
echo "char_convert: $NAME converted; $NSET value(s) set ($KINDS); wrote $OUTCHAR"
exit 0
