#!/bin/bash
# The -convert fixture guard and conversion oracle (Task 10 of
# docs/superpowers/plans/2026-08-24-save-schema-v1.md; plan constraint 7).
#
# What it proves, in three parts:
#
#   1. REFUSAL. `-convert` on either committed evidence fixture
#      (docs/evidence/inc-upw.13/Furious_Fox.sav, Jaoin.sav) exits 3,
#      prints a refusal naming the fixture rule, and leaves the fixture
#      byte-identical -- including when the fixture is reached through a
#      symlink from outside docs/evidence/, because the guard matches the
#      REALPATH, not the argument string. No .v0 sibling may appear.
#
#   2. CONVERSION. A scratch COPY of Furious_Fox.sav converts -- against a
#      module whose numbering matches the save. The fixture predates
#      4ba035b (which added the immolation Effect), so the sandbox module
#      is compiled from HEAD scripts with lib/m_items.irh AND lib/main.irc
#      reverted to `git show 4ba035b^` -- the exact procedure the spec's
#      Compatibility section prescribes for save/Dench.sav, rehearsed here
#      on a disposable copy. Asserted: exit 0; a <name>.v0 sibling holds
#      the original v0 bytes; the converted file's header reads the current
#      SaveSchemaID(); and tools/dump_save.sh of the converted copy AGAINST
#      THE REPO'S HEAD MODULE matches the dump of the .v0 against the
#      matching (pre-4ba035b) module line for line except the Format: line
#      and the renumbered rID values -- the conversion records the module
#      manifest, so the reader converts each saved rID by POSITION and the
#      reading survives the module rebuild that used to shift it.
#
#      THIS PART IS ALSO THE APPEND-ONLY ORACLE. It is the check that fails
#      if a new resource is ever declared in the middle of an array again:
#      the fixture then reads back as different equipment. On 2026-08-25 it
#      did exactly that, which is how 4ba035b's mid-file declaration was
#      found and moved to the end of lib/main.irc.
#      Also: converting against the MISMATCHED (HEAD) module refuses
#      cleanly (exit 2, target byte-identical, no .v0 left); a pre-existing
#      .v0 sibling refuses (exit 3, nothing overwritten); re-converting an
#      already-v1 file refuses (exit 2 -- there is no v0 to back up).
#
#   3. NOTHING REAL TOUCHED. The real save/ directory's contents (names AND
#      bytes) are unchanged, no tracked file under docs/evidence/ or lib/
#      changed, and the repo's own mod/ is untouched.
#
# Needs BOTH builds (same requirement as tools/check_flavor_stability.sh):
# ./incursion (the developer build carries -compile) for the sandbox module,
# and ${INCURSION_BIN:-./incursion-headless} for the conversions and dumps.
# Needs git history: the pre-4ba035b lib files come from `git show`.
#
# Usage: tools/check_convert_guard.sh   (exits 0 on pass, 1 on fail)
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

BIN="${INCURSION_BIN:-./incursion-headless}"
COMPILER=./incursion
FIX_DIR="$ROOT/docs/evidence/inc-upw.13"

[ -x "$BIN" ] || { fail "$BIN is not built. Run: BACKEND=posix ./build_macos.sh"; exit 1; }
[ -x "$COMPILER" ] || { fail "$COMPILER is not built. Run: ./build_macos.sh"; exit 1; }
[ -f "$FIX_DIR/Furious_Fox.sav" ] || { fail "fixture Furious_Fox.sav is missing"; exit 1; }
[ -f "$FIX_DIR/Jaoin.sav" ] || { fail "fixture Jaoin.sav is missing"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-convguard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Contents, not just names: -convert rewrites its target in place, so a file
# list alone would miss a real save being silently rewritten.
save_state() { find "$ROOT/save" -type f -print0 2>/dev/null | sort -z | xargs -0 md5 2>/dev/null; }
REAL_SAVE_BEFORE="$(save_state)"

# Two INCURSIONPATH sandboxes (the tools/dump_save.sh technique), so that
# anything the binary wrongly wrote by CWD lands in a throwaway directory:
#   SB      the repo's own HEAD module -- for the refusal tests and the
#           module-MISMATCH test.
#   SB_PRE  a module compiled from HEAD scripts with lib/m_items.irh
#           and lib/main.irc reverted to pre-4ba035b -- the module that
#           matches the fixture's
#           numbering, for the real conversion.
# -timeout bounds a regressed binary that fell through to the menu;
# INCURSION_MAX_KEYS starves that menu of input so it dies fast.
SB="$WORK/sandbox"
mkdir -p "$SB/save" "$SB/logs"
ln -sfn "$ROOT/mod" "$SB/mod"
ln -sfn "$ROOT/lib" "$SB/lib"

SB_PRE="$WORK/pre4ba035b"
mkdir -p "$SB_PRE/mod" "$SB_PRE/save" "$SB_PRE/logs"
cp -R "$ROOT/lib" "$SB_PRE/lib"
ln -sfn "$ROOT/inc" "$SB_PRE/inc"
# BOTH files, not just m_items.irh. 4ba035b first declared the immolation
# Effect in the MIDDLE of m_items.irh, which slid 862 later Effects down one
# place; the declaration now lives at the END of main.irc so that the same
# commit reads as a legal append. Reverting only m_items.irh therefore no
# longer removes that resource, and the sandbox module stopped matching the
# fixture. Reverting both files to 4ba035b^ reconstructs the fixture's
# numbering exactly: measured 2026-08-25 by reading both modules' own save
# manifests, the two lists differ by that one appended Effect and nothing
# else.
for f in lib/m_items.irh lib/main.irc; do
    if ! git -C "$ROOT" show "4ba035b^:$f" > "$SB_PRE/$f"; then
        fail "git show 4ba035b^:$f failed; is history available?"
        exit 1
    fi
done
INCURSIONPATH="$SB_PRE/" "$COMPILER" -compile main.irc \
    < /dev/null > "$WORK/compile.log" 2>&1
STATUS=$?
if [ "$STATUS" -ne 0 ] || [ ! -f "$SB_PRE/mod/Incursion.Mod" ]; then
    tail -15 "$WORK/compile.log"
    fail "the pre-4ba035b sandbox module compile failed (exit $STATUS)"
    exit 1
fi

# SB_PLUS: HEAD scripts plus ONE throwaway appended Effect, for the
# module-MISMATCH test below.
#
# That test used to borrow its mismatch from the repo's own module, on the
# assumption that HEAD always carried a resource the fixture predates -- the
# immolation Effect. Release 3 took that Effect back out so that a release-2
# save converts cleanly, at which point HEAD and SB_PRE held the same
# resources, there was no mismatch left to detect, and all four of the
# mismatch assertions failed. A check must not change meaning because
# unrelated content moved, so it now BUILDS the module it needs: one extra
# Effect, appended at the end, which is the smallest legal edit that grows
# szEff by one and so makes the fixture's memory segment too short.
SB_PLUS="$WORK/headplus"
mkdir -p "$SB_PLUS/mod" "$SB_PLUS/save" "$SB_PLUS/logs"
cp -R "$ROOT/lib" "$SB_PLUS/lib"
ln -sfn "$ROOT/inc" "$SB_PLUS/inc"
cat >> "$SB_PLUS/lib/main.irc" <<'EFFECT'

0 Effect "convert guard probe" : EA_GENERIC
  { On Event META(EV_TURN) { return NOTHING; }; }
EFFECT
INCURSIONPATH="$SB_PLUS/" "$COMPILER" -compile main.irc \
    < /dev/null > "$WORK/compile_plus.log" 2>&1
STATUS=$?
if [ "$STATUS" -ne 0 ] || [ ! -f "$SB_PLUS/mod/Incursion.Mod" ]; then
    tail -15 "$WORK/compile_plus.log"
    fail "the HEAD-plus-one-Effect sandbox module compile failed (exit $STATUS)"
    exit 1
fi

convert() { # <sandbox> <path> <logfile>
    INCURSIONPATH="$1/" INCURSION_MAX_KEYS=40 \
        "$BIN" -headless -timeout 60 -convert "$2" > "$3" 2>&1 < /dev/null
}

# --- 1. the committed fixtures refuse, by resolved path --------------------
for FIX in Furious_Fox.sav Jaoin.sav; do
    cp "$FIX_DIR/$FIX" "$WORK/$FIX.pre"
    convert "$SB" "docs/evidence/inc-upw.13/$FIX" "$WORK/$FIX.out"
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
convert "$SB" "$WORK/innocent_name.sav" "$WORK/symlink.out"
STATUS=$?
if [ "$STATUS" -ne 3 ]; then
    tail -5 "$WORK/symlink.out"
    fail "-convert through a symlink into docs/evidence/ exited $STATUS, wanted 3"
fi
cmp -s "$FIX_DIR/Furious_Fox.sav" "$WORK/Furious_Fox.sav.pre" || \
    fail "the symlinked fixture's bytes changed"

# --- 2a. the MISMATCHED module refuses with the target untouched -----------
# The fixture's memory segment is one Effect short of SB_PLUS, so that
# module needs more bytes than the save holds. -convert must see that BEFORE any
# write: exit 2, the file byte-identical, no .v0 left behind. This is the
# protection the real save relies on if the operator fumbles the module
# revert, so it is proven here first.
cp "$FIX_DIR/Furious_Fox.sav" "$WORK/copy_mismatch.sav"
convert "$SB_PLUS" "$WORK/copy_mismatch.sav" "$WORK/mismatch.out"
STATUS=$?
if [ "$STATUS" -ne 2 ]; then
    tail -8 "$WORK/mismatch.out"
    fail "-convert against the mismatched (HEAD+1 Effect) module exited $STATUS, wanted 2"
fi
grep -qi "does not match" "$WORK/mismatch.out" || \
    fail "the mismatch refusal does not say the module does not match the save"
cmp -s "$WORK/copy_mismatch.sav" "$FIX_DIR/Furious_Fox.sav" || \
    fail "the mismatched-module run changed the target file; it must refuse before writing"
[ ! -e "$WORK/copy_mismatch.sav.v0" ] || \
    fail "the mismatched-module run left a .v0 behind; it must refuse before writing"

# --- 2b. a scratch copy converts against the MATCHING module ---------------
cp "$FIX_DIR/Furious_Fox.sav" "$WORK/copy.sav"
convert "$SB_PRE" "$WORK/copy.sav" "$WORK/copy.out"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    tail -15 "$WORK/copy.out"
    fail "-convert on a scratch copy (matching module) exited $STATUS, wanted 0"
else
    [ -f "$WORK/copy.sav.v0" ] || fail "conversion left no copy.sav.v0 backup"
    cmp -s "$WORK/copy.sav.v0" "$FIX_DIR/Furious_Fox.sav" || \
        fail "copy.sav.v0 does not hold the original v0 bytes"
    cmp -s "$WORK/copy.sav" "$WORK/copy.sav.v0" && \
        fail "the converted file is byte-identical to the original; nothing was converted"

    # The comparisons below drop Format: (v0 digest vs the v1 stamp, the one
    # intended difference) and File: (the two paths differ by name).
    strip() { grep -v -e '^Format:' -e '^File:' "$1"; }
    # The cross-module comparison additionally masks rID VALUES (the
    # sed below): a module-slotted rID prints as a 167xxxxx/168xxxxx
    # decimal (slot 1's base is 1<<24 = 16777216), and resources in pools
    # AFTER Eff legitimately renumber by +1 across this exact module pair
    # -- that renumbering is what the schema makes survivable; the NAMES
    # on the same lines are the content. No other dump numeral reaches 16
    # million.

    # Dump the .v0 against the MATCHING module (direct invocation: the
    # tools/dump_save.sh wrapper always symlinks the repo's own mod/ in,
    # which is the wrong module for a v0 read of this save; the wrapper's
    # leftover check is replicated at the bottom).
    INCURSIONPATH="$SB_PRE/" "$BIN" -headless -timeout 60 \
        -dump "$WORK/copy.sav.v0" > "$WORK/dumpOld.txt" 2> "$WORK/dumpOld.err" < /dev/null
    STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        cat "$WORK/dumpOld.err"
        fail "-dump of the .v0 backup (matching module) exited $STATUS"
    fi
    grep -Eq '^Format: *SF' "$WORK/dumpOld.txt" || \
        fail "the .v0 backup's Format line is not a v0 SF digest: $(grep '^Format:' "$WORK/dumpOld.txt")"

    # STRICT: the converted file, read against the SAME matching module,
    # must dump line for line with the v0 original -- the conversion
    # itself is lossless.
    INCURSIONPATH="$SB_PRE/" "$BIN" -headless -timeout 60 \
        -dump "$WORK/copy.sav" > "$WORK/dumpPre.txt" 2> "$WORK/dumpPre.err" < /dev/null
    STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        cat "$WORK/dumpPre.err"
        fail "-dump of the converted copy (matching module) exited $STATUS"
    fi
    if ! diff <(strip "$WORK/dumpOld.txt") <(strip "$WORK/dumpPre.txt") > "$WORK/dumpPre.diff"; then
        echo "--- first differing dump lines (v0 vs converted, SAME module) ---"
        head -12 "$WORK/dumpPre.diff"
        fail "under the matching module the converted copy's dump differs from the v0's beyond Format:/File: -- the conversion is lossy"
    fi

    # ACROSS THE REBUILD: the converted file read against the repo's HEAD
    # module. The names it now carries must resolve to the same resources,
    # so with the renumbered rID VALUES masked the dump must be identical
    # -- the spec's survivability claim, rehearsed on the copy.
    if ! INCURSION_DUMP_SANDBOX="$WORK/dumpNew" INCURSION_BIN="$BIN" \
            ./tools/dump_save.sh "$WORK/copy.sav" > "$WORK/dumpNew.txt" 2> "$WORK/dumpNew.err"; then
        cat "$WORK/dumpNew.err"
        fail "-dump of the converted copy (HEAD module) exited non-zero"
    fi
    grep -Eq "^Format: *${SCHEMA_STAMP//./\\.}$" "$WORK/dumpNew.txt" || \
        fail "the converted copy's Format line is not $SCHEMA_STAMP: $(grep '^Format:' "$WORK/dumpNew.txt")"
    # The "Known Spells" section is EXCLUDED from this comparison: it is
    # printed from Character::Spells[], which is indexed by module spell
    # POSITION, not by rID or name -- the documented conversion ceiling
    # (the ponytail comment at inc/Creature.h:877). Across this module
    # pair the one known spell's slot points at a different spell; that is
    # the pre-existing v0 ceiling, not a conversion defect, and it shifts
    # identically whether or not the file is converted. Measured 2026-08-25:
    # with rIDs masked and this section dropped, the remaining diff of a
    # 1500-line dump is empty; without the exclusion it is exactly the one
    # Known Spells line.
    xmod() { strip "$1" | sed -E 's/16[0-9]{6}/RID/g' | sed '/^Known Spells:/,/^$/d'; }
    if ! diff <(xmod "$WORK/dumpOld.txt") <(xmod "$WORK/dumpNew.txt") > "$WORK/dump.diff"; then
        echo "--- first differing dump lines (v0 @ matching module vs converted @ HEAD, rIDs masked) ---"
        head -12 "$WORK/dump.diff"
        fail "beyond renumbered rID values and the positional Known Spells ceiling, the converted copy's HEAD-module dump differs from the v0 reading"
    fi

    # An existing .v0 sibling must refuse: it is the only v0 copy, and a
    # second conversion overwriting it would destroy the original bytes.
    cp "$FIX_DIR/Furious_Fox.sav" "$WORK/copy2.sav"
    printf 'sentinel: not a save\n' > "$WORK/copy2.sav.v0"
    convert "$SB_PRE" "$WORK/copy2.sav" "$WORK/copy2.out"
    STATUS=$?
    [ "$STATUS" -eq 3 ] || \
        fail "-convert with a pre-existing .v0 sibling exited $STATUS, wanted 3 (refused)"
    cmp -s "$WORK/copy2.sav" "$FIX_DIR/Furious_Fox.sav" || \
        fail "copy2.sav changed even though its .v0 sibling should have refused the conversion"
    grep -q 'sentinel' "$WORK/copy2.sav.v0" || \
        fail "the pre-existing copy2.sav.v0 was overwritten"

    # An already-v1 file has no v0 bytes to back up: refuse, do not rewrite.
    convert "$SB_PRE" "$WORK/copy.sav" "$WORK/again.out"
    STATUS=$?
    [ "$STATUS" -eq 2 ] || \
        fail "-convert on an already-v1 file exited $STATUS, wanted 2"
fi

# --- 3. nothing real was touched -------------------------------------------
LEFTOVERS="$(find "$SB/save" "$SB/logs" "$SB_PRE/save" "$SB_PRE/logs" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$LEFTOVERS" != "0" ]; then
    find "$SB/save" "$SB/logs" "$SB_PRE/save" "$SB_PRE/logs" -type f
    fail "the binary wrote $LEFTOVERS file(s) into a sandbox; -convert may write only its target and the .v0"
fi
REAL_SAVE_AFTER="$(save_state)"
if [ "$REAL_SAVE_BEFORE" != "$REAL_SAVE_AFTER" ]; then
    fail "the real save/ directory's contents changed during this check"
fi
if ! git -C "$ROOT" diff --quiet -- docs/evidence lib; then
    fail "tracked files under docs/evidence/ or lib/ changed during this check"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: both fixtures (and a symlink to one) refused with exit 3 and"
    echo "      stayed byte-identical; the mismatched HEAD module refused with"
    echo "      the target untouched; a scratch copy converted to $SCHEMA_STAMP against"
    echo "      the matching pre-4ba035b module with a byte-exact .v0 backup"
    echo "      and a dump identical across the module rebuild beyond Format:;"
    echo "      a pre-existing .v0 refused; nothing real was touched."
    exit 0
fi
exit 1
