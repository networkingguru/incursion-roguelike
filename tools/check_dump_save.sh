#!/bin/bash
# Regression check for `-dump` / tools/dump_save.sh (src/Dump.cpp, bd inc-loa.1).
#
# What it protects. -dump exists so a real save can be inspected without
# playing the game. If a struct layout change, a Sheet.cpp edit, or a Dump.cpp
# edit silently breaks the walk, the acceptance criterion for inc-loa.1 is
# that this fails LOUDLY -- not that the report quietly starts omitting a
# section, or worse, printing something plausible and wrong.
#
# How it gets a known save without one checked into git. save/ is gitignored
# (a .sav is a memory image welded to the exact struct layout of the binary
# that wrote it, so a committed fixture would go stale the moment anyone
# touched a header -- the same reason an external parser was rejected for
# -dump itself; see docs/ENGINE-SERIALISATION.md). Instead this generates one
# fresh, in a scratch directory, the same way tools/check_headless.sh does:
# tools/headless.sh with a fixed seed and tools/keys/smoke.keys is
# deterministic (same reasoning as check_headless.sh's reproducibility
# assertion), so the fields checked below are exact expected values, not just
# "something non-empty".
#
# Usage: tools/check_dump_save.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

SEED=1
KEYS="tools/keys/smoke.keys"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-dumpcheck.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

if [ ! -x ./incursion-headless ]; then
    fail "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
fi

# Baseline for the safety assertion in step 4: the real save/ directory's file
# count, taken before anything below runs.
REAL_SAVE_BEFORE="$(find "$ROOT/save" -type f 2>/dev/null | sort)"

# 1. Produce a known save. This writes into $WORK/run/save, never into the
#    real save/ -- see tools/headless.sh's own header comment.
INCURSION_RUN_DIR="$WORK/run" ./tools/headless.sh "$KEYS" "$SEED" \
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

# Content: with seed 1 and smoke.keys's chargen.keys, character generation is
# deterministic (same premise tools/check_headless.sh relies on for its own
# reproducibility assertion), so these are exact values, not just "present".
grep -qE '^Name:      Varag the Deathbringer$' "$WORK/dump.txt" ||
    fail "Name: line missing or does not read 'Varag the Deathbringer' -- character generation, the save format, or -dump's field walk has changed"
grep -qE '^HP:        42 / 42' "$WORK/dump.txt" ||
    fail "HP: line missing or not '42 / 42' -- current/max HP no longer reads correctly"
grep -qE '^Format:    IS1\.0$' "$WORK/dump.txt" ||
    fail "Format: line missing or not IS1.0 -- real saves are v1 now, and -dump names the FILE's stamp"
grep -qE 'Race   Orc' "$WORK/dump.txt" ||
    fail "the engine's own character-sheet dump (CreateCharDump) did not include the expected race line"

# 3b. The SAME save, through the graphical binary. src/Dump.cpp has always been
#     linked into ./incursion, but until 2026-08-18 nothing there parsed -dump,
#     so the capability was in the shipped release and unreachable. The parse
#     now lives in src/Wlibtcod.cpp's main(), mirroring src/Wposix.cpp:530-539.
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

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: -dump produced every required section, the exact expected"
    echo "      fields for a deterministic seed, and wrote nothing"
    if [ "$GUI_CHECKED" = yes ]; then
        echo "      Both backends were checked and their reports are identical."
    else
        echo "      HEADLESS BACKEND ONLY -- the graphical -dump path was skipped."
    fi
    exit 0
fi
exit 1
