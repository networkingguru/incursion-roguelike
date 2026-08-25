#!/bin/bash
# The spec's flavour-stability oracle (docs/SAVE-SCHEMA-SPEC.md, "The
# resource memory segment"; Task 9 of
# docs/superpowers/plans/2026-08-24-save-schema-v1.md).
#
# What it proves: a v1 save's per-player resource memory -- the flavour
# appearance assigned to every potion/scroll Effect and its Known/Tried
# identification flags -- survives a module rebuild that ADDS a resource.
# That is exactly the renumbering defect the v1 schema exists to fix: the
# old raw MDataSeg block keyed rows by position and stored flavour rIDs as
# raw numbers, so one added Effect shifted every appearance (the 4ba035b
# defect class).
#
# How:
#   1. Deterministic seed-1 smoke session; keep its save. Dump it against
#      the repo's own module and extract the "Effect Memory" section
#      (src/Dump.cpp prints it with the real EFFMEM accessors).
#   2. In an INCURSIONPATH sandbox, rebuild the module with one scratch
#      Effect appended to a COPY of lib/m_items.irh (the
#      tools/check_dup_names.sh technique; unique name).
#   3. Dump the SAME save against the sandbox module.
#   4. Assert the two Effect Memory sections are line-for-line identical:
#      every appearance and every Known/Tried flag unchanged.
#
# REVERSE CONTROL (run once, 2026-08-25, before the segment-record fix was
# implemented -- HEAD a7978db, the raw-MDataSeg IS1.1 format of Task 6/7,
# with only the Effect Memory dump section added so both runs use the same
# lens): this check FAILED at step 4 as it must. 389 of 391 effect-memory
# lines differed; every flavour appearance shifted to a DIFFERENT flavour,
# because the stored flavour rIDs are raw numbers and the flavour pool's
# base moved when szEff grew. First lines of that failing diff, verbatim
# (< repo module, > module + 1 scratch Effect, same save both times):
#
#   <   Giant Strength: flavor=clasped pflavor=- Known=0 Tried=0 ...
#   <   Ogre Power: flavor=sharp-edged pflavor=- Known=0 Tried=0 ...
#   <   Might: flavor=chipped pflavor=- Known=0 Tried=0 ...
#   >   Giant Strength: flavor=buckled pflavor=- Known=0 Tried=0 ...
#   >   Ogre Power: flavor=rusted pflavor=- Known=0 Tried=0 ...
#   >   Might: flavor=banded pflavor=- Known=0 Tried=0 ...
#   FAIL: 389 of 391 effect-memory lines changed after a one-Effect rebuild
#
# With the segment record (name-keyed rows, flavour rIDs through the name
# table) the same comparison is line-for-line identical and this PASSES.
#
# Needs BOTH builds: ./incursion (graphical developer build; -compile lives
# behind DEBUG, same requirement as tools/check_dup_names.sh) for the module
# rebuild, and ${INCURSION_BIN:-./incursion-headless} for the session and
# the dumps.
#
# Usage: tools/check_flavor_stability.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

BIN="${INCURSION_BIN:-./incursion-headless}"
COMPILER=./incursion
SEED=1
KEYS="tools/keys/smoke.keys"

[ -x "$BIN" ] || { fail "$BIN is not built. Run: BACKEND=posix ./build_macos.sh"; exit 1; }
[ -x "$COMPILER" ] || { fail "$COMPILER is not built. Run: ./build_macos.sh"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-flavstab.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

REAL_SAVE_BEFORE="$(find "$ROOT/save" -type f 2>/dev/null | sort)"

# --- 1. a real session produces the save, and dump A reads it against the
#        repo's own module (tools/dump_save.sh symlinks $ROOT/mod in) -------
INCURSION_RUN_DIR="$WORK/run1" INCURSION_BIN="$BIN" ./tools/headless.sh \
    "$KEYS" "$SEED" > "$WORK/session.log" 2>&1 < /dev/null
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    tail -20 "$WORK/session.log"
    fail "the smoke session exited $STATUS, wanted 0"
    exit 1
fi
SAVE="$(ls "$WORK"/run1/save/*.sav 2>/dev/null | head -1)"
[ -n "$SAVE" ] || { fail "the session produced no .sav file"; exit 1; }

if ! INCURSION_DUMP_SANDBOX="$WORK/dumpA" INCURSION_BIN="$BIN" \
        ./tools/dump_save.sh "$SAVE" > "$WORK/dumpA.txt" 2> "$WORK/dumpA.err"; then
    cat "$WORK/dumpA.err"
    fail "dump A (repo module) exited non-zero"
    exit 1
fi

extract_mem() { # <dump.txt> -> the Effect Memory section's body lines
    awk '/^=== Effect Memory/{f=1;next} /^===/{f=0} f && NF' "$1"
}
extract_mem "$WORK/dumpA.txt" > "$WORK/memA.txt"
MEM_COUNT="$(wc -l < "$WORK/memA.txt" | tr -d ' ')"
if [ "$MEM_COUNT" -eq 0 ]; then
    fail "dump A has no effect-memory lines: SetFlavors state is missing from the save, or the dump section is gone"
    exit 1
fi

# --- 2. the sandbox module: the same scripts plus ONE scratch Effect ------
SB="$WORK/plus1"
mkdir -p "$SB/mod" "$SB/save" "$SB/logs"
cp -R "$ROOT/lib" "$SB/lib"
ln -sfn "$ROOT/inc" "$SB/inc"
cat >> "$SB/lib/m_items.irh" <<'EOF'

AI_STONE Effect "Scratch Flavour Stability Probe" : EA_GRANT
  { xval: ADJUST; yval: A_WIS; pval: PLUS_1PER1;
    Flags: EF_NEEDS_PLUS, EF_NAMEONLY; SC_THE; Level: PLUS_2PER1;
    Desc: "A scratch effect appended by tools/check_flavor_stability.sh.";
    Lists:
      * ITEM_COST ABIL_BOOST_COST(150); }
EOF

INCURSIONPATH="$SB/" "$COMPILER" -compile main.irc \
    < /dev/null > "$WORK/compile.log" 2>&1
STATUS=$?
if [ "$STATUS" -ne 0 ] || [ ! -f "$SB/mod/Incursion.Mod" ]; then
    tail -15 "$WORK/compile.log"
    fail "the sandbox module compile failed (exit $STATUS)"
    exit 1
fi
if cmp -s "$SB/mod/Incursion.Mod" "$ROOT/mod/Incursion.Mod"; then
    fail "the sandbox module is byte-identical to the repo's -- the scratch Effect did not land, so this check would prove nothing"
    exit 1
fi

# --- 3. dump B: the SAME save against the sandbox module ------------------
# Direct INCURSIONPATH invocation (the tools/dump_save.sh wrapper always
# symlinks the repo's own mod/ in, which would defeat step 3), with the
# wrapper's leftover check replicated below.
SAVE_ABS="$(cd "$(dirname "$SAVE")" && pwd)/$(basename "$SAVE")"
INCURSIONPATH="$SB/" "$BIN" -dump "$SAVE_ABS" \
    > "$WORK/dumpB.txt" 2> "$WORK/dumpB.err"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    cat "$WORK/dumpB.err"
    fail "dump B (sandbox module) exited $STATUS -- the save does not even load against a module with one added Effect"
fi
LEFTOVERS="$(find "$SB/save" "$SB/logs" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$LEFTOVERS" != "0" ]; then
    find "$SB/save" "$SB/logs" -type f
    fail "-dump wrote $LEFTOVERS file(s) into the sandbox; it must be read-only"
fi

# --- 4. every appearance line and every Known/Tried flag unchanged --------
extract_mem "$WORK/dumpB.txt" > "$WORK/memB.txt"
if ! diff "$WORK/memA.txt" "$WORK/memB.txt" > "$WORK/mem.diff"; then
    CHANGED="$(grep -c '^<' "$WORK/mem.diff")"
    echo "--- first differing effect-memory lines ---"
    head -12 "$WORK/mem.diff"
    fail "$CHANGED of $MEM_COUNT effect-memory lines changed after a one-Effect rebuild -- flavour appearances / Known state did not survive"
fi

# The scratch Effect itself must NOT have gained a memory row: the save
# carries no row for it, so it keeps zeroed memory, as a new game gives it.
if grep -q "Scratch Flavour Stability Probe" "$WORK/memB.txt"; then
    fail "the scratch Effect appears in the effect-memory dump; a resource with no row must keep zeroed memory"
fi

# --- 5. nothing real was touched ------------------------------------------
REAL_SAVE_AFTER="$(find "$ROOT/save" -type f 2>/dev/null | sort)"
if [ "$REAL_SAVE_BEFORE" != "$REAL_SAVE_AFTER" ]; then
    fail "the real save/ directory's file list changed during this check"
fi
if ! git -C "$ROOT" diff --quiet -- lib mod; then
    fail "tracked files under lib/ or mod/ changed during this check"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: all $MEM_COUNT flavour appearances and Known/Tried flags"
    echo "      survived a module rebuild with one added Effect, and the"
    echo "      added Effect kept zeroed memory."
    exit 0
fi
exit 1
