#!/bin/bash
# gate: live
# Regression check for `-dump` / tools/dump_save.sh (src/Dump.cpp, bd inc-loa.1).
#
# What it protects. -dump exists so a real save can be inspected without
# playing the game. If a struct layout change, a Sheet.cpp edit, or a Dump.cpp
# edit silently breaks the walk, the acceptance criterion for inc-loa.1 is
# that this fails LOUDLY -- not that the report quietly starts omitting a
# section, or worse, printing something plausible and wrong.
#
# How it gets a known save without one checked into git. save/ is gitignored.
# A v0 .sav is a memory image welded to the exact struct layout of the binary
# that wrote it, so a committed v0 fixture would go stale the moment anyone
# touched a header -- the same reason an external parser was rejected for
# -dump itself; see docs/ENGINE-SERIALISATION.md. The v1 saves the game
# writes today are tagged-record files and do not go stale that way, but a
# committed fixture would freeze one old writer's output where this check
# wants today's: the point is that TODAY's writer and TODAY's reader agree.
# So this generates one fresh, in a scratch directory, the same way
# tools/check_headless.sh does, with tools/headless.sh, a fixed seed and
# tools/keys/smoke.keys.
#
# WHERE THE EXPECTED VALUES COME FROM, AND WHY NOT A LITERAL. They used to be
# literals -- Name 'Varag the Deathbringer', HP '42 / 42', Race 'Orc' -- which
# was only sound while seed 1 rolled that exact character forever. Content
# changes move what a seed rolls: e19cc46 (2026-09-18) gave Heal a scroll form,
# seed 1 stopped rolling Varag, and this check failed on the literal before it
# ever reached its real assertions. The literals are gone; each field is now
# compared against an INDEPENDENT record the SAME session wrote through a path
# that is not -dump, so the check proves today's save writer and today's -dump
# reader agree on the character and cannot go stale when the content moves:
#
#   Name, Race  logs/charprobe.txt in the run directory. Game::SaveGame calls
#               the engine's own DumpCharacter (src/Registry.cpp:1105-1111)
#               under INCURSION_CHAR_PROBE=1, writing the saved character in
#               the engine's own words. The banner's first line is
#               "<Named>, <personality>[...]", so Name is the text before the
#               first comma; Race is the 'Race   <name>' basics line.
#   HP          no top-level HP line is written by DumpCharacter, so it is read
#               from the run's final screen dump (logs/screens/*shutdown*),
#               whose status line the terminal itself wrote: 'HP:<cur>/<max>'.
#               That is still a record of the session and not of -dump.
#
# For a field with no independent record the check would say so and assert it
# non-empty and well-formed instead; every field it checks has one today.
#
# --prove-red walks the same dance tools/check_lib.sh's check_mutation does,
# but builds PRIVATELY: the mutation is in src/Dump.cpp, so it compiles to its
# own OUT=incursion-dumpcheck-probe with a non-empty EXTRA_CXXFLAGS= (the pair
# that makes build_macos.sh skip its shared mod/Incursion.Mod rewrite). The
# shared ./incursion-headless and mod/Incursion.Mod are never touched; their
# checksums are recorded before and compared after.
#
# Usage: tools/check_dump_save.sh   (exits 0 on pass, 1 on fail)
# The current schema stamp, read from the source of truth rather than
# hardcoded: a literal here rots into a false failure the moment SCHEMA_REV
# moves, and the check then reports a format problem that does not exist.
SCHEMA_STAMP="IS1.$(sed -n 's/^#define SCHEMA_REV \([0-9]*\).*/\1/p' src/SaveV1.cpp)"
[ -n "${SCHEMA_STAMP#IS1.}" ] || { echo "cannot read SCHEMA_REV from src/SaveV1.cpp" >&2; exit 1; }
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

PROVE_RED=0
[ "${1:-}" = "--prove-red" ] && PROVE_RED=1

SEED=1
KEYS="tools/keys/smoke.keys"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-dumpcheck.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# INCURSION_BIN is what --prove-red points at its private probe build; an
# ordinary run leaves it unset and gets the shared ./incursion-headless. Both
# callers below (headless.sh, dump_save.sh) read the same variable, so naming
# it here threads it through without a second spelling.
BIN="${INCURSION_BIN:-./incursion-headless}"
if [ ! -x "$BIN" ]; then
    fail "$BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
fi

# Baseline for the safety assertion in step 4: the real save/ directory's file
# count, taken before anything below runs.
REAL_SAVE_BEFORE="$(find "$ROOT/save" -type f 2>/dev/null | sort)"

# 1. Produce a known save. This writes into $WORK/run/save, never into the
#    real save/ -- see tools/headless.sh's own header comment.
# INCURSION_CHAR_PROBE=1 is the independent record: it makes Game::SaveGame
# write logs/charprobe.txt beside the save (src/Registry.cpp:1105-1111), which
# step 3 compares the -dump report against.
# Measured exit 1 under 08-13 and 0 under 08-18; 08-13 cannot finish character generation.
INCURSION_RUN_DIR="$WORK/run" INCURSION_CHAR_PROBE=1 \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-18.dat ./tools/headless.sh "$KEYS" "$SEED" \
    > "$WORK/session.log" 2>&1 < /dev/null
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    echo "--- session output ---"
    tail -20 "$WORK/session.log"
    fail "the session that was supposed to produce a save exited $STATUS, wanted 0"
    exit 1
fi

SAVE="$(ls "$WORK"/run/save/*.sav 2>/dev/null | head -1)"
if [ -z "$SAVE" ]; then
    fail "the session produced no .sav file; nothing to dump"
    exit 1
fi

# 2. Dump it through the real wrapper -- the same path the oracle brief and
#    any other caller is told to use, not the binary directly.
if ! INCURSION_DUMP_SANDBOX="$WORK/dumpsandbox" ./tools/dump_save.sh "$SAVE" \
        > "$WORK/dump.txt" 2> "$WORK/dump.stderr"; then
    echo "--- dump_save.sh stderr ---"
    cat "$WORK/dump.stderr"
    fail "tools/dump_save.sh exited non-zero on a save it just wrote"
fi

# 3. The report has to actually be there, in shape and in exact content.
#    Structural: every section the acceptance criterion names must appear.
for section in \
    "=== Incursion save dump ===" \
    "=== Equipped Slots ===" \
    "=== Player Stati ===" \
    "=== Inventory (recursive into containers) ===" \
    "=== On The Ground (at player position, recursive) ===" \
    "=== Full Character Sheet ==="
do
    grep -qF "$section" "$WORK/dump.txt" || fail "missing section: $section"
done

# The Format line names the FILE's own stamp, read from SCHEMA_REV's source of
# truth above, so a literal here cannot rot into a false format complaint.
grep -qE "^Format:    ${SCHEMA_STAMP//./\\.}$" "$WORK/dump.txt" ||
    fail "Format: line missing or not $SCHEMA_STAMP -- real saves are v1 now, and -dump names the FILE's stamp"

# Content, each field read from an independent record of the SAME session (see
# the header). Nothing below is the value a previous seed happened to roll.
PROBE="$WORK/run/logs/charprobe.txt"
if [ ! -f "$PROBE" ]; then
    fail "no logs/charprobe.txt -- INCURSION_CHAR_PROBE=1 should have made Game::SaveGame write one; without it the Name and Race fields have no independent record to compare against"
fi

# Name: the banner's first line is "<Named>, <personality>[ (Explore Mode)]"
# (src/Sheet.cpp:24-29), centered in the 80-column sheet, so it is trimmed and
# everything before the first comma is p->Named -- exactly what -dump's Name:
# line prints.
PROBE_NAME=""
[ -f "$PROBE" ] && PROBE_NAME="$(sed -n '1s/,.*//p' "$PROBE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
DUMP_NAME="$(sed -n 's/^Name:      //p' "$WORK/dump.txt" | head -1)"
if [ -z "$PROBE_NAME" ]; then
    fail "charprobe.txt has no banner first line, so the Name field has no independent record; cannot check it"
elif [ "$DUMP_NAME" != "$PROBE_NAME" ]; then
    fail "Name: -dump reads '$DUMP_NAME' but the engine's own DumpCharacter wrote '$PROBE_NAME' -- the save writer and the -dump reader disagree, or -dump's Name walk is wrong"
fi

# Race: charprobe's basics block is '<field>   <value>' (src/Sheet.cpp:37-38);
# the dump repeats the same 'Race   <name>' line from CreateCharDump.
PROBE_RACE="$(sed -n 's/^Race   //p' "$PROBE" 2>/dev/null | head -1)"
DUMP_RACE="$(grep -m1 '^Race   ' "$WORK/dump.txt" | sed 's/^Race   //')"
if [ -z "$PROBE_RACE" ]; then
    fail "charprobe.txt has no 'Race   ' line, so the Race field has no independent record; cannot check it"
elif [ "$DUMP_RACE" != "$PROBE_RACE" ]; then
    fail "Race: -dump reads '$DUMP_RACE' but the engine's own DumpCharacter wrote '$PROBE_RACE' -- the save writer and the -dump reader disagree about the character's race"
fi

# HP: DumpCharacter writes no top-level HP field (charprobe has only journal
# 'H:cur/max' lines, which are entry-time snapshots, not the current value), so
# HP is read from the run's final screen dump. Its status line was written by
# the terminal itself (posixTerm::DumpScreen, src/Wposix.cpp) during the same
# session, not by -dump, and it holds 'HP:<cur>/<max>'.
HP_SCREEN="$(ls "$WORK"/run/logs/screens/*shutdown*.txt 2>/dev/null | head -1)"
PROBE_HP=""
[ -n "$HP_SCREEN" ] && \
    PROBE_HP="$(grep -oE 'HP:[0-9]+/[0-9]+' "$HP_SCREEN" | head -1 | sed 's/^HP://; s|/| / |')"
DUMP_HP="$(sed -n 's/^HP: *\([0-9][0-9]*\) \/ \([0-9][0-9]*\).*/\1 \/ \2/p' "$WORK/dump.txt" | head -1)"
if [ -z "$PROBE_HP" ]; then
    fail "the run's shutdown screen is missing or carries no 'HP:cur/max' status line, so the HP field has no independent record; cannot check it"
elif [ "$DUMP_HP" != "$PROBE_HP" ]; then
    fail "HP: -dump reads '$DUMP_HP' but the session's own status line read '$PROBE_HP' -- current/max HP no longer reads correctly"
fi

# 3b. The SAME save, through the graphical binary. src/Dump.cpp has always been
#     linked into ./incursion, but until 2026-08-18 nothing there parsed -dump,
#     so the capability was in the shipped release and unreachable. The parse
#     now lives in src/Wlibtcod.cpp's main(), mirroring src/Wposix.cpp:537-562.
#     If anyone removes it, this step goes red -- which is the only reason the
#     step exists. The two backends share every line of Dump.cpp and Sheet.cpp,
#     so the reports must be byte-identical; a difference means one backend is
#     walking the save differently and that is a defect either way.
GUI_CHECKED=no
if [ -x ./incursion ]; then
    GUI_CHECKED=yes
    if ! INCURSION_BIN=./incursion \
            INCURSION_DUMP_SANDBOX="$WORK/dumpsandbox-gui" \
            ./tools/dump_save.sh "$SAVE" \
            > "$WORK/dump-gui.txt" 2> "$WORK/dump-gui.stderr"; then
        echo "--- graphical -dump stderr ---"
        cat "$WORK/dump-gui.stderr"
        fail "./incursion could not run -dump; the parse in src/Wlibtcod.cpp's main() is missing or broken"
    elif ! diff -q "$WORK/dump.txt" "$WORK/dump-gui.txt" > /dev/null; then
        echo "--- first 20 differing lines ---"
        diff "$WORK/dump.txt" "$WORK/dump-gui.txt" | head -20
        fail "the two backends disagree about the same save; they share Dump.cpp, so one of them walks it wrongly"
    fi
else
    echo "SKIP: ./incursion is not built, so the graphical -dump path was NOT"
    echo "      checked. Run ./build_macos.sh to cover it."
fi

# 4. The safety claim, re-asserted independently of dump_save.sh's own check:
#    nothing must have been written to, removed from, or changed in the real
#    save/ directory by any of this -- not by the game session in step 1
#    (which used INCURSION_RUN_DIR and should never have touched it), and not
#    by the dump in step 2.
REAL_SAVE_AFTER="$(find "$ROOT/save" -type f 2>/dev/null | sort)"
if [ "$REAL_SAVE_BEFORE" != "$REAL_SAVE_AFTER" ]; then
    fail "the real save/ directory's file list changed during this check"
fi
for sandbox in "$WORK/dumpsandbox" "$WORK/dumpsandbox-gui"; do
    if [ -d "$sandbox" ]; then
        fail "tools/dump_save.sh left $(basename "$sandbox") behind: something was written where nothing should be"
    fi
done

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi

# ---------------------------------------------------------------------------
# --prove-red. The mutation is in src/Dump.cpp and prints a constant where the
# Name field belongs, so the independent-record comparison above must go red.
# It is built PRIVATELY: OUT=incursion-dumpcheck-probe with a non-empty
# EXTRA_CXXFLAGS=, the pair build_macos.sh:375 uses to skip its shared
# mod/Incursion.Mod rewrite, so neither the shared binary nor the shared module
# is touched. Both are checksummed around the whole dance. Unlike
# tools/check_lib.sh's check_mutation this does not rebuild the shared target,
# which is what lets the check carry '# gate: live' with no '# gate-serial:'.
if [ "$PROVE_RED" = 1 ]; then
    SELF="$ROOT/tools/check_dump_save.sh"
    PROBE_BIN="incursion-dumpcheck-probe"
    ORIG_DUMP="$WORK/Dump.cpp.orig"

    echo
    echo "--- prove-red: break src/Dump.cpp's Name walk and rebuild privately ---"
    SHARED_BEFORE="$(shasum -a 256 "$ROOT/incursion-headless" | awk '{print $1}')"
    MOD_BEFORE="$(shasum -a 256 "$ROOT/mod/Incursion.Mod" | awk '{print $1}')"

    cp -p "$ROOT/src/Dump.cpp" "$ORIG_DUMP" || {
        echo "prove-red: cannot copy src/Dump.cpp aside" >&2; exit 2; }
    # Restore on every exit path, including the build failing or an interrupt:
    # this function edits tracked source and losing the original is the one
    # outcome it must make impossible.
    trap 'cp -p "$ORIG_DUMP" "$ROOT/src/Dump.cpp" 2>/dev/null; rm -f "$PROBE_BIN"; rm -rf "$WORK"' EXIT INT TERM HUP

    FROM='printf("Name:      %s\n", (const char*)p->Named);'
    TO='printf("Name:      Mutated Constant\n");'
    if [ "$(grep -cF "$FROM" "$ROOT/src/Dump.cpp")" != 1 ]; then
        echo "prove-red: the Name print line appears not exactly once in src/Dump.cpp; the mutation site has moved" >&2
        exit 2
    fi
    # Literal replacement, via python: the fragment is C++ full of characters
    # sed reads as live syntax, so sed is the wrong tool (check_lib.sh says so).
    FROM="$FROM" TO="$TO" python3 -c '
import os
p = "src/Dump.cpp"
s = open(p, encoding="utf-8", errors="surrogateescape").read()
a, b = os.environ["FROM"], os.environ["TO"]
open(p, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(a, b))
' || { echo "prove-red: the replacement failed" >&2; exit 2; }

    echo "  building $PROBE_BIN (private OUT=, non-empty EXTRA_CXXFLAGS=) ..."
    if ! EXTRA_CXXFLAGS="-DDUMPCHECK_PROVE_RED" OUT="$PROBE_BIN" BACKEND=posix \
            ./build_macos.sh > "$WORK/prove-build.log" 2>&1; then
        echo "--- private build output ---"
        tail -20 "$WORK/prove-build.log"
        echo "prove-red: the private probe build failed" >&2
        exit 2
    fi

    INNER=0
    INCURSION_BIN="$PROBE_BIN" "$SELF" > "$WORK/prove-run.log" 2>&1 || INNER=$?

    echo "  restoring src/Dump.cpp and removing the probe binary"
    cp -p "$ORIG_DUMP" "$ROOT/src/Dump.cpp" || {
        echo "prove-red: THE RESTORE DID NOT TAKE; original kept at $ORIG_DUMP" >&2; exit 2; }
    rm -f "$PROBE_BIN"
    trap 'rm -rf "$WORK"' EXIT INT TERM HUP

    case "$INNER" in
        1) echo "  ok    the check exits 1 against a -dump that prints a constant Name" ;;
        0) echo "  FAIL  the check PASSED with the Name walk broken, so it measures nothing" >&2
           tail -15 "$WORK/prove-run.log" | sed 's/^/        /'
           exit 1 ;;
        *) echo "prove-red: the inner run exited $INNER (neither pass 0 nor fail 1), so nothing is proved" >&2
           tail -15 "$WORK/prove-run.log" | sed 's/^/        /'
           exit 2 ;;
    esac

    SHARED_AFTER="$(shasum -a 256 "$ROOT/incursion-headless" | awk '{print $1}')"
    MOD_AFTER="$(shasum -a 256 "$ROOT/mod/Incursion.Mod" | awk '{print $1}')"
    if [ "$SHARED_BEFORE" != "$SHARED_AFTER" ]; then
        echo "prove-red: THE SHARED ./incursion-headless CHANGED during the run" >&2
        exit 2
    fi
    if [ "$MOD_BEFORE" != "$MOD_AFTER" ]; then
        echo "prove-red: THE SHARED mod/Incursion.Mod CHANGED during the run" >&2
        exit 2
    fi
    echo "  ok    ./incursion-headless and mod/Incursion.Mod are byte-identical (private build)"
    echo
    echo "PROVED RED: with src/Dump.cpp's Name walk broken, this check exits 1."
    exit 0
fi

if [ "$GUI_CHECKED" = yes ]; then
    echo "PASS: -dump produced every required section, the fields matched the"
    echo "      session's own independent records, and it wrote nothing."
    echo "      Both backends were checked and their reports are identical."
else
    echo "PASS: -dump produced every required section, the fields matched the"
    echo "      session's own independent records, and it wrote nothing."
    echo "      HEADLESS BACKEND ONLY -- the graphical -dump path was skipped."
fi
exit 0
