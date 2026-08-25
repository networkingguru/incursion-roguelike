#!/bin/bash
# Regression check: a save that fails part way through must leave the game
# running, usable, and able to save again (src/Registry.cpp, bd inc-i0r).
#
# What it protects. Registry::SaveGroup parks each object's data-block HANDLE
# in the object's own POINTER field while it writes the object out, and swaps
# the pointers back in a loop that used to sit after every write. Any throw
# from the write path -- a full disk is the ordinary way -- skipped that loop,
# so every object the writer had reached kept a small integer where a pointer
# belonged. The next walk over them dereferenced it: Game::Cleanup,
# EXC_BAD_ACCESS at 0x7f3, which is the handle 2035, exit 139.
#
# The dangerous half is a PART-WAY failure. The objects already visited hold
# handles and the objects not yet reached hold real pointers, so a restore that
# simply re-walked the whole group would hand a genuine pointer to GetData()
# and corrupt what it was repairing. SaveFixupScope therefore unwinds exactly
# the objects it recorded as converted, and this check exists to prove that the
# recorded set is the right one at several different failure points.
#
# WHY A STAGED FAILURE AND NOT A FULL DISK. Every write in SaveGroup's two
# loops goes into a CFile, which is a memory file; the disk is not touched
# until CFile::CommitCompressed, after both loops. So a genuinely full disk can
# only ever fail with EVERY object already converted, and the part-way case has
# no other way in. INCURSION_SAVE_FAIL_AT (src/Registry.cpp) stages the throw
# at a chosen object or data block instead. The full-disk case was reproduced
# by hand as well, before and after the fix; it is not automated here because
# it needs a mounted disk image.
#
# HOW IT WOULD CATCH A REGRESSION. Three ways, in rising order of subtlety:
#   1. the session crashes (this is what the unfixed build does: exit 139);
#   2. the session survives but the failure was never reported to the player;
#   3. the session survives and reports, but the character it goes on to save
#      is not the character an unfailed session would have saved. That is the
#      silent half-restore, and it is why every run below is compared field for
#      field against a control run of the same seed and the same key script
#      with no failure staged.
#
# Usage: tools/check_save_fail.sh   (exits 0 on pass, 1 on fail)
#
# Set INCURSION_BIN to pick which build drives the check
# (default ./incursion-headless).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

BIN="${INCURSION_BIN:-./incursion-headless}"
export INCURSION_BIN="$BIN"
SEED=1
KEYS="tools/keys/save-fail.keys"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-savefail.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

if [ ! -x "$BIN" ]; then
    fail "$BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
fi

# Every reported field of the character, with the two things that cannot be the
# same in two runs taken out:
#   the File: line, because each run has its own scratch directory;
#   the Secs column of the Level Statistics table, because
#     Player::StoreLevelStats (src/Player.cpp:2766) accumulates
#     time(NULL) - start_second, so it measures how long the machine took and
#     not anything about the character. It has been seen to differ by one
#     between two runs of the same seed. Nothing else in the report is a clock:
#     every other field matched exactly across every run this was written
#     against.
dump_of() {
    INCURSION_DUMP_SANDBOX="$2/dumpsandbox" ./tools/dump_save.sh "$1" 2>&1 |
        grep -v '^File:' |
        sed -E 's/^([0-9]+ *\|[^|]*\|[^|]*\|[^|]*\|)[^|]*\|/\1<secs>|/'
}

# One session. $1 is the value for INCURSION_SAVE_FAIL_AT, or "" for the
# control run. Leaves $WORK/<tag>/ behind for the caller to look at.
run_session() {
    local at="$1" tag="$2"
    mkdir -p "$WORK/$tag"
    if [ -n "$at" ]; then
        INCURSION_SAVE_FAIL_AT="$at" INCURSION_RUN_DIR="$WORK/$tag/run" \
            ./tools/headless.sh "$KEYS" "$SEED" \
            > "$WORK/$tag/session.log" 2>&1 < /dev/null
    else
        INCURSION_RUN_DIR="$WORK/$tag/run" \
            ./tools/headless.sh "$KEYS" "$SEED" \
            > "$WORK/$tag/session.log" 2>&1 < /dev/null
    fi
    echo $? > "$WORK/$tag/status"
}

# 1. The control. Same seed, same keys, nothing staged: this is what the
#    character is supposed to look like.
run_session "" control
STATUS="$(cat "$WORK/control/status")"
if [ "$STATUS" -ne 0 ]; then
    echo "--- control session output ---"
    tail -20 "$WORK/control/session.log"
    fail "the control session exited $STATUS, wanted 0; nothing below can mean anything"
    exit 1
fi
CONTROL_SAVE="$(ls "$WORK"/control/run/save/*.sav 2>/dev/null | head -1)"
if [ -z "$CONTROL_SAVE" ]; then
    fail "the control session produced no .sav file"
    exit 1
fi
dump_of "$CONTROL_SAVE" "$WORK/control" > "$WORK/control.dump"
grep -q '^Name:' "$WORK/control.dump" || {
    echo "--- control dump ---"
    head -20 "$WORK/control.dump"
    fail "the control save would not dump; the check cannot compare against it"
    exit 1
}

# 2. The staged failures. Plain numbers count objects, and 1 is the first --
#    so this covers a failure on the very first object and two part way
#    through the object loop (which is the case the whole design turns on).
#    The "d" values (data blocks) were retired when real saves flipped to the
#    v1 schema: SaveGroupV1 writes no data-block section at all
#    (FIELD_STR/FIELD_BLOB inline their contents; groupHeader.dataCount is
#    always 0), so a failure staged there would simply never fire and the run
#    would prove nothing.
for AT in 1 5 40; do
    TAG="fail-$AT"
    run_session "$AT" "$TAG"
    STATUS="$(cat "$WORK/$TAG/status")"

    # 2a. Survived. The unfixed build dies here with 139 (SIGSEGV).
    if [ "$STATUS" -ne 0 ]; then
        echo "--- session output for INCURSION_SAVE_FAIL_AT=$AT ---"
        tail -20 "$WORK/$TAG/session.log"
        fail "INCURSION_SAVE_FAIL_AT=$AT: session exited $STATUS, wanted 0 (139 is the crash in Game::Cleanup this check exists for)"
        continue
    fi

    # 2b. Reported. A failure the player is not told about is not a pass.
    grep -q "Error writing save file" "$WORK/$TAG/session.log" ||
        fail "INCURSION_SAVE_FAIL_AT=$AT: no write error was reported, so the staged failure never happened and this run proves nothing"

    # 2c. Still playing. "Autosave...  Failed." is Main.cpp's own line, and it
    #     is on a screen dumped after the save, so the game drew a frame after
    #     the failure instead of dying at it.
    grep -qs "Failed" "$WORK/$TAG"/run/logs/screens/*after-save* ||
        fail "INCURSION_SAVE_FAIL_AT=$AT: the screen dumped after the failed save does not show the failure; the session may not have got past it"

    # 2d. Saved again, to a place that works.
    SAVE="$(ls "$WORK/$TAG"/run/save/*.sav 2>/dev/null | head -1)"
    if [ -z "$SAVE" ]; then
        fail "INCURSION_SAVE_FAIL_AT=$AT: the session produced no .sav file, so the save AFTER the failed one did not work"
        continue
    fi

    # 2e. And the character in it is the control's character, exactly. This is
    #     the step that catches a restore that half-works.
    dump_of "$SAVE" "$WORK/$TAG" > "$WORK/$TAG.dump"
    if ! diff -q "$WORK/control.dump" "$WORK/$TAG.dump" > /dev/null; then
        echo "--- first 20 differing lines (control vs INCURSION_SAVE_FAIL_AT=$AT) ---"
        diff "$WORK/control.dump" "$WORK/$TAG.dump" | head -20
        fail "INCURSION_SAVE_FAIL_AT=$AT: the character saved after the failure is not the character the control saved"
    fi
done

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: a save failing at the first object, part way through the object"
    echo "      loop, and inside the data loop each left the game running, told"
    echo "      the player, and saved the same character afterwards."
fi
exit "$FAILED"
