#!/bin/bash
# The -convert fixture guard and the old-v0 refusal (Task 10 of
# docs/superpowers/plans/2026-08-24-save-schema-v1.md; plan constraint 7;
# bead inc-vqla).
#
# Since inc-vqla widened Character::Spells[] to 32 bits, sizeof(Player) no
# longer matches the layout every v0 (raw-dump) save was written with, so
# this binary cannot read a v0 save at all. It refuses one with a message
# that sends the player to release 4, which reads it and saves it as v1.
# Before inc-vqla this check also converted a scratch copy of the v0
# fixture and was the append-only oracle; the committed v1 character
# fixtures (tools/fixtures/chars/, refused on a SLIDE or SHUFFLE by the
# manifest check) and tools/check_v1_append_survives.sh carry that now.
#
# What it proves:
#
#   1. FIXTURE GUARD. `-convert` on either committed evidence fixture
#      (docs/evidence/inc-upw.13/Furious_Fox.sav, Jaoin.sav) exits 3,
#      prints a refusal naming the fixture rule, and leaves the fixture
#      byte-identical -- including when the fixture is reached through a
#      symlink from outside docs/evidence/, because the guard matches the
#      REALPATH, not the argument string. No .v0 sibling may appear.
#
#   2. OLD-v0 REFUSAL. A scratch COPY of each fixture (outside
#      docs/evidence/) refuses: exit 2, the message names release 4, the
#      copy is byte-identical, and no .v0 sibling appears.
#
#   3. ALREADY-v1. A scratch copy of a committed v1 character fixture
#      refuses with exit 2 and stays byte-identical (there is no v0 to
#      back up).
#
#   4. NOTHING REAL TOUCHED. The real save/ directory's contents (names AND
#      bytes) are unchanged, and no tracked file under docs/evidence/ or
#      lib/ changed.
#
# Usage: tools/check_convert_guard.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

BIN="${INCURSION_BIN:-./incursion-headless}"
FIX_DIR="$ROOT/docs/evidence/inc-upw.13"
V1_FIX="$ROOT/tools/fixtures/chars/human-priest-mage-seed4-gate.sav"

[ -x "$BIN" ] || { fail "$BIN is not built. Run: BACKEND=posix ./build_macos.sh"; exit 1; }
[ -f "$FIX_DIR/Furious_Fox.sav" ] || { fail "fixture Furious_Fox.sav is missing"; exit 1; }
[ -f "$FIX_DIR/Jaoin.sav" ] || { fail "fixture Jaoin.sav is missing"; exit 1; }
[ -f "$V1_FIX" ] || { fail "v1 fixture $V1_FIX is missing"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-convguard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Contents, not just names: -convert rewrites its target in place, so a file
# list alone would miss a real save being silently rewritten.
save_state() { find "$ROOT/save" -type f -print0 2>/dev/null | sort -z | xargs -0 md5 2>/dev/null; }
REAL_SAVE_BEFORE="$(save_state)"
# A snapshot, not "no diff": an uncommitted build output such as a
# regenerated lib/dispatch.h is not this check's doing.
tracked_state() { git -C "$ROOT" diff -- docs/evidence lib | md5; }
TRACKED_BEFORE="$(tracked_state)"

# An INCURSIONPATH sandbox (the tools/dump_save.sh technique), so that
# anything the binary wrongly wrote by CWD lands in a throwaway directory.
# -timeout bounds a regressed binary that fell through to the menu;
# INCURSION_MAX_KEYS starves that menu of input so it dies fast.
SB="$WORK/sandbox"
mkdir -p "$SB/save" "$SB/logs"
ln -sfn "$ROOT/mod" "$SB/mod"
ln -sfn "$ROOT/lib" "$SB/lib"

convert() { # <path> <logfile>
    INCURSIONPATH="$SB/" INCURSION_MAX_KEYS=40 \
        "$BIN" -headless -timeout 60 -convert "$1" > "$2" 2>&1 < /dev/null
}

# --- 1. the committed fixtures refuse, by resolved path --------------------
for FIX in Furious_Fox.sav Jaoin.sav; do
    cp "$FIX_DIR/$FIX" "$WORK/$FIX.pre"
    convert "docs/evidence/inc-upw.13/$FIX" "$WORK/$FIX.out"
    STATUS=$?
    if [ "$STATUS" -ne 3 ]; then
        tail -5 "$WORK/$FIX.out"
        fail "-convert on the fixture $FIX exited $STATUS, wanted 3 (refused)"
    fi
    grep -qi "evidence" "$WORK/$FIX.out" || \
        fail "the $FIX refusal does not name the fixture rule (no 'evidence' in the output)"
    cmp -s "$FIX_DIR/$FIX" "$WORK/$FIX.pre" || \
        fail "the fixture $FIX is no longer byte-identical after the refused -convert"
    [ ! -e "$FIX_DIR/$FIX.v0" ] || \
        fail "a $FIX.v0 backup appeared next to the fixture; the refusal must precede any write"
done

# The guard must match the REALPATH: a symlink from outside docs/evidence/
# into it must still refuse, or the guard is string-matching its argument.
ln -s "$FIX_DIR/Furious_Fox.sav" "$WORK/innocent_name.sav"
convert "$WORK/innocent_name.sav" "$WORK/symlink.out"
STATUS=$?
if [ "$STATUS" -ne 3 ]; then
    tail -5 "$WORK/symlink.out"
    fail "-convert through a symlink into docs/evidence/ exited $STATUS, wanted 3"
fi
cmp -s "$FIX_DIR/Furious_Fox.sav" "$WORK/Furious_Fox.sav.pre" || \
    fail "the symlinked fixture's bytes changed"

# --- 2. a scratch copy of an old v0 save refuses, untouched ----------------
for FIX in Furious_Fox.sav Jaoin.sav; do
    cp "$FIX_DIR/$FIX" "$WORK/copy_$FIX"
    convert "$WORK/copy_$FIX" "$WORK/copy_$FIX.out"
    STATUS=$?
    if [ "$STATUS" -ne 2 ]; then
        tail -5 "$WORK/copy_$FIX.out"
        fail "-convert on a scratch copy of the v0 $FIX exited $STATUS, wanted 2 (refused)"
    fi
    grep -q "release 4" "$WORK/copy_$FIX.out" || \
        fail "the v0 $FIX refusal does not tell the player to use release 4"
    cmp -s "$WORK/copy_$FIX" "$FIX_DIR/$FIX" || \
        fail "the refused v0 copy of $FIX changed; it must refuse before writing"
    [ ! -e "$WORK/copy_$FIX.v0" ] || \
        fail "the refused v0 copy of $FIX left a .v0 behind; it must refuse before writing"
done

# --- 3. an already-v1 file refuses, untouched -------------------------------
cp "$V1_FIX" "$WORK/v1copy.sav"
convert "$WORK/v1copy.sav" "$WORK/v1copy.out"
STATUS=$?
[ "$STATUS" -eq 2 ] || \
    { tail -5 "$WORK/v1copy.out"; fail "-convert on an already-v1 file exited $STATUS, wanted 2"; }
cmp -s "$WORK/v1copy.sav" "$V1_FIX" || \
    fail "the already-v1 copy changed; -convert must not rewrite it"
[ ! -e "$WORK/v1copy.sav.v0" ] || \
    fail "the already-v1 copy left a .v0 behind"

# --- 4. nothing real was touched -------------------------------------------
LEFTOVERS="$(find "$SB/save" "$SB/logs" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$LEFTOVERS" != "0" ]; then
    find "$SB/save" "$SB/logs" -type f
    fail "the binary wrote $LEFTOVERS file(s) into the sandbox; a refused -convert may write nothing"
fi
REAL_SAVE_AFTER="$(save_state)"
if [ "$REAL_SAVE_BEFORE" != "$REAL_SAVE_AFTER" ]; then
    fail "the real save/ directory's contents changed during this check"
fi
if [ "$TRACKED_BEFORE" != "$(tracked_state)" ]; then
    fail "tracked files under docs/evidence/ or lib/ changed during this check"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: both fixtures (and a symlink to one) refused with exit 3 and"
    echo "      stayed byte-identical; scratch copies of both v0 saves refused"
    echo "      with exit 2 and the release-4 message, untouched; an already-v1"
    echo "      file refused untouched; nothing real was touched."
    exit 0
fi
exit 1
