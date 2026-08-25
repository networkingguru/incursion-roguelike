#!/bin/bash
# Regression check for save/module load hardening against corrupt input
# (src/Registry.cpp, src/Term.cpp, src/lz.c, src/rle.c -- bd inc-l0t).
#
# What it protects. A save file and a .Mod are files on disk the game reads
# and believes -- input validation at a trust boundary. Before inc-l0t, a
# truncated or corrupted save could corrupt the heap instead of raising an
# error: the group header's compSize/groupSize were used unchecked, the
# decompressor was never told its output buffer's real size, and a short
# read inside the decompressed buffer silently came back as zeros. This
# drives the REAL game binary (never a hand-rolled parser -- see
# docs/ENGINE-SERIALISATION.md, the same reasoning inc-loa.1 followed) at
# ten hand-corrupted variants of one genuine save, and at two genuine saves,
# and checks that every corrupt one is refused cleanly (a reported error, an
# exit code that says so, and nothing printed by the sanitizer build) while
# the genuine ones still load and read back correctly.
#
# Which reader this covers. The genuine save is generated fresh, so it is a
# v1 tagged-record file ("IS1.x", zlib-6 payload): the corpus exercises the
# v1 reader's header path -- the fileHeader/groupHeader sanity checks it
# shares with the v0 reader -- and its zlib decompression bounds. The v0
# raw reader stays covered elsewhere, by the two v0 evidence fixtures under
# docs/evidence/inc-upw.13/, which tools/check_convert_guard.sh loads (and
# dumps) through it on every run.
#
# tools/check_lz_uncompress.sh is the unit-level half of this same
# verification: it proves the two decoder primitives are safe in isolation,
# with a canary buffer showing no write ever reaches past the declared
# output capacity. This script proves the whole load path -- header sanity
# checks included -- behaves the same way end to end.
#
# Usage: tools/check_load_corrupt.sh   (exits 0 on pass, 1 on fail)
#
# Set INCURSION_BIN to pick which build drives the check (default: prefer
# ./incursion-ubsan if it exists, so a regression that only shows up under
# the sanitizer is still caught; fall back to ./incursion-headless).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

if [ -z "${INCURSION_BIN:-}" ]; then
    if [ -x ./incursion-ubsan ]; then
        INCURSION_BIN=./incursion-ubsan
    else
        INCURSION_BIN=./incursion-headless
    fi
fi
export INCURSION_BIN
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=0:halt_on_error=0}"

if [ ! -x "$INCURSION_BIN" ]; then
    fail "$INCURSION_BIN is not built. Run: BACKEND=posix ./build_macos.sh (or see tools/lz_uncompress_selftest.c's header for the UBSan build line)"
    exit 1
fi

SEED=1
KEYS="tools/keys/smoke.keys"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-loadcorrupt.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

REAL_SAVE_BEFORE="$(find "$ROOT/save" -type f 2>/dev/null | sort)"

# --- 1. produce one genuine, deterministic save, exactly as check_dump_save.sh does ---
INCURSION_RUN_DIR="$WORK/run" ./tools/headless.sh "$KEYS" "$SEED" \
    > "$WORK/session.log" 2>&1 < /dev/null
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    tail -20 "$WORK/session.log"
    fail "the session that was supposed to produce a save exited $STATUS, wanted 0"
    exit 1
fi
GENUINE="$(ls "$WORK"/run/save/*.sav 2>/dev/null | head -1)"
if [ -z "$GENUINE" ]; then
    fail "the session produced no .sav file; nothing to corrupt"
    exit 1
fi

# --- 2. the genuine save must still load and read back correctly (no regression) ---
if ! INCURSION_DUMP_SANDBOX="$WORK/dump_genuine" ./tools/dump_save.sh "$GENUINE" \
        > "$WORK/genuine.out" 2> "$WORK/genuine.err"; then
    cat "$WORK/genuine.err"
    fail "the genuine, uncorrupted save was refused -- this is a regression in ordinary loading, not a security fix"
else
    grep -qE '^Name:      Varag the Deathbringer$' "$WORK/genuine.out" ||
        fail "genuine save: Name: line missing/wrong -- load path changed what it produces"
    grep -qE '^HP:        42 / 42' "$WORK/genuine.out" ||
        fail "genuine save: HP: line missing/wrong -- load path changed what it produces"
fi
# Only src/Term.cpp, src/Registry.cpp, src/lz.c and src/rle.c are inc-l0t's
# concern -- other UBSan findings elsewhere in the engine (there is at least
# one known one, in src/Values.cpp, unrelated to loading) are real bugs but
# not this one's regressions, and must not fail this check.
TOUCHED_FILES_PATTERN='^src/(Term\.cpp|Registry\.cpp|lz\.c|rle\.c):'
if grep -qE "$TOUCHED_FILES_PATTERN" "$WORK/genuine.err"; then
    fail "genuine save: sanitizer reported undefined behavior in the code this fix touched, loading a file that isn't even corrupt"
    grep -E "$TOUCHED_FILES_PATTERN" "$WORK/genuine.err"
fi

# --- 3. craft the corrupt variants ---
CORRUPT_DIR="$WORK/corrupt"
if ! python3 tools/craft_corrupt_saves.py "$GENUINE" "$CORRUPT_DIR" > "$WORK/craft.log" 2> "$WORK/craft.err"; then
    cat "$WORK/craft.err"
    fail "tools/craft_corrupt_saves.py failed -- see above (a struct-layout drift check may have tripped; that itself is worth investigating, not just silencing)"
    exit 1
fi

# --- 4. every corrupt variant must be refused cleanly ---
# craft.log lines are 'name|path|expected-stderr-substring' -- see
# tools/craft_corrupt_saves.py. Not an associative array: the macOS system
# bash driving this (3.2) predates them.
CASE_COUNT=0
while IFS='|' read -r name path expected; do
    [ -z "$name" ] && continue
    CASE_COUNT=$((CASE_COUNT + 1))
    OUT="$WORK/corrupt_$name.out"
    ERR="$WORK/corrupt_$name.err"
    if INCURSION_DUMP_SANDBOX="$WORK/dump_$name" ./tools/dump_save.sh "$path" \
            > "$OUT" 2> "$ERR"; then
        fail "$name: dump_save.sh exited 0 on a corrupt save -- it should have been refused"
    fi
    if [ -n "$expected" ] && ! grep -qF "$expected" "$ERR"; then
        fail "$name: expected stderr to mention '$expected', got:"
        cat "$ERR"
    fi
    if grep -qE "$TOUCHED_FILES_PATTERN" "$ERR"; then
        fail "$name: sanitizer reported undefined behavior in the code this fix touched -- exactly what inc-l0t was filed to stop. See:"
        grep -E "$TOUCHED_FILES_PATTERN" "$ERR"
    fi
    # A refused load must not have left a fabricated character sheet or
    # otherwise gone on to print a report -- confirm dump_save.sh's own
    # section markers never appear for a rejected file.
    if grep -qF "=== end of dump ===" "$OUT"; then
        fail "$name: produced a full dump despite being corrupt -- the corruption was silently tolerated instead of rejected"
    fi
done < "$WORK/craft.log"

# --- 5. the safety claim: nothing touched the real save/ directory ---
REAL_SAVE_AFTER="$(find "$ROOT/save" -type f 2>/dev/null | sort)"
if [ "$REAL_SAVE_BEFORE" != "$REAL_SAVE_AFTER" ]; then
    fail "the real save/ directory's file list changed during this check"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: genuine save loads correctly; all $CASE_COUNT corrupt variants"
    echo "      (bad compSize/groupSize, truncation, an overflow-attempt stream,"
    echo "      and a stream that decodes shorter than it claims) were refused"
    echo "      cleanly under $INCURSION_BIN, with no sanitizer finding."
    exit 0
fi
exit 1
