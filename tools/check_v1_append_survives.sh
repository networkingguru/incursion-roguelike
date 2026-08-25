#!/bin/bash
# The payoff of the module manifest: a save written BEFORE a resource is
# appended to lib/ still loads to the same character AFTER the append
# (docs/SAVE-SCHEMA-SPEC.md, "Resource references"; phase 3 of
# docs/superpowers/plans/2026-08-25-save-manifest-position-refs.md).
#
# WHY AN EFFECT, AND WHY THIS IS SHARP. Effect is array 3 of 21. Appending
# one leaves every Effect position alone but pushes the running index of
# EVERY LATER ARRAY up by one -- Artifact, Quest, Dungeon, Routine, NPC,
# Class, Race, Domain, God, Region, Terrain, Text, Variable, Template,
# Flavour, Behaviour, Encounter. A character references its Race and its
# Class, both of which sit after Effect. So a reader that took the saved rID
# at face value would hand back the resource one place earlier and the dump
# would name a different race or class. The manifest is what turns the saved
# rID into (array, position) and back again through the loaded lengths.
#
# The append goes at the END of lib/main.irc, which is the end of parse
# order, so the new Effect takes the LAST Effect position. That is a legal
# append under the project's append-only rule; it is not a reorder.
#
# The append is PROVED, not assumed: the check reads the Effect length out
# of each save's own manifest and requires the appended module's to be
# exactly one greater. Without that, a silently ineffective edit would make
# this check pass while testing nothing.
#
# Usage: tools/check_v1_append_survives.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

if [ ! -x ./incursion-headless ]; then
    fail "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-append.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
MODULE="$WORK/module"

# 1. The sandbox module: a copy of lib/ with one Effect appended. inc/ is a
#    symlink because the compiler reads it and nothing here writes to it.
mkdir -p "$MODULE/mod" "$MODULE/save" "$MODULE/logs"
cp -Rf "$ROOT/lib" "$MODULE/lib" || { fail "could not copy lib/"; exit 1; }
ln -sfn "$ROOT/inc" "$MODULE/inc"

{
    printf '\n\n'
    printf 'Effect "Append Oracle Effect" : EA_NOTIMP\n'
    printf '  { Level: 1; }\n'
} >> "$MODULE/lib/main.irc"

INCURSIONPATH="$MODULE/" ./incursion-headless -compile main.irc \
    < /dev/null > "$WORK/compile.log" 2>&1
if [ ! -f "$MODULE/mod/Incursion.Mod" ]; then
    echo "--- compile output ---"
    tail -30 "$WORK/compile.log"
    fail "the appended sandbox module did not compile"
    exit 1
fi

# 2. The save, written by the STOCK module. Raw mode leaves the records
#    uncompressed so the manifest can be read back below.
INCURSION_V1_RAW=1 INCURSION_RUN_DIR="$WORK/before" \
    ./tools/headless.sh tools/keys/smoke.keys 1 \
    > "$WORK/session.log" 2>&1 < /dev/null
SAVE="$(ls "$WORK"/before/save/*.sav 2>/dev/null | head -1)"
if [ -z "$SAVE" ]; then
    echo "--- session output ---"
    tail -20 "$WORK/session.log"
    fail "the session that was supposed to produce a save produced none"
    exit 1
fi

# 3. The same session against the APPENDED module, only to read ITS manifest.
#    tools/headless.sh forces INCURSIONPATH to its own run directory and
#    symlinks the repo's mod/ and lib/ into it, so passing INCURSIONPATH here
#    does nothing. Running IN the sandbox module instead gets the right
#    module: "ln -sfn $ROOT/mod $MODULE/mod" cannot replace $MODULE/mod,
#    because that is a real directory and not a symlink -- it drops an inert
#    $MODULE/mod/mod link inside it and leaves the compiled module alone.
INCURSION_V1_RAW=1 INCURSION_RUN_DIR="$MODULE" \
    ./tools/headless.sh tools/keys/smoke.keys 1 \
    > "$WORK/session-after.log" 2>&1 < /dev/null
SAVE_AFTER="$(ls "$MODULE"/save/*.sav 2>/dev/null | head -1)"
if [ -z "$SAVE_AFTER" ]; then
    echo "--- session output ---"
    tail -20 "$WORK/session-after.log"
    fail "no save was written under the appended module"
    exit 1
fi

eff_len() { # <raw save> -> the manifest's Effect array length
    python3 - "$1" <<'PY'
import sys, struct
b = open(sys.argv[1], 'rb').read()
# tag 4, K_ARRAY(11), count 21, elemSize 4, then 21 uint32 lengths.
i = b.find(struct.pack('<HBII', 4, 11, 21, 4))
if i < 0:
    sys.exit("no manifest in the save")
print(struct.unpack_from('<I', b, i + 11 + 4 * 3)[0])   # SP_EFF is array 3
PY
}

BEFORE_EFF="$(eff_len "$SAVE")"      || { fail "no manifest in the stock save"; exit 1; }
AFTER_EFF="$(eff_len "$SAVE_AFTER")" || { fail "no manifest in the appended save"; exit 1; }
if [ "$AFTER_EFF" != "$((BEFORE_EFF + 1))" ]; then
    fail "the append did not take: Effect array is $BEFORE_EFF before and $AFTER_EFF after, wanted $((BEFORE_EFF + 1))"
    exit 1
fi
echo "append proved: Effect array $BEFORE_EFF -> $AFTER_EFF"

# 4. The stock save, read by the STOCK module. The control.
if ! INCURSION_DUMP_SANDBOX="$WORK/sb-stock" ./tools/dump_save.sh "$SAVE" \
        > "$WORK/before.txt" 2> "$WORK/before.err"; then
    echo "--- dump stderr ---"
    tail -5 "$WORK/before.err"
    fail "the stock save did not load against the stock module"
    exit 1
fi

# 5. THE POINT: the same save, read by the APPENDED module.
INCURSIONPATH="$MODULE/" ./incursion-headless -dump "$SAVE" \
    < /dev/null > "$WORK/after.txt" 2> "$WORK/after.err"
if [ $? -ne 0 ]; then
    echo "--- dump stderr ---"
    tail -10 "$WORK/after.err"
    fail "the pre-append save did NOT load against the appended module"
    exit 1
fi

# 6. THE SIGNAL. The dump prints the dungeon's raw rID, and that number MUST
#    change: Dungeon is array 6, after Effect at array 3, so appending one
#    Effect pushes every Dungeon rID up by exactly one. A reader that took
#    the saved rID at face value would print the SAME number and would then
#    be pointing one place earlier in the loaded module. So "unchanged" is
#    the failure here, and "+1" is the proof the conversion ran.
did() { sed -n 's/.*dID=\([0-9][0-9]*\).*/\1/p' "$1" | head -1; }
BEFORE_DID="$(did "$WORK/before.txt")"
AFTER_DID="$(did "$WORK/after.txt")"
if [ -z "$BEFORE_DID" ] || [ -z "$AFTER_DID" ]; then
    fail "the dump printed no dID -- this check cannot see the conversion"
elif [ "$AFTER_DID" = "$BEFORE_DID" ]; then
    fail "dID stayed $BEFORE_DID across the append -- the saved rID was taken at face value, not converted"
elif [ "$AFTER_DID" != "$((BEFORE_DID + 1))" ]; then
    fail "dID went $BEFORE_DID -> $AFTER_DID across a one-Effect append, wanted $((BEFORE_DID + 1))"
else
    echo "converted: dungeon rID $BEFORE_DID -> $AFTER_DID across the append"
fi

# 7. EVERYTHING ELSE identical. The File: line carries the sandbox path each
#    dump was told, and the rID numbers are step 6's business, so both are
#    masked. What is left is the character, and it must not move.
norm() { sed -e '/^File:/d' -e 's/dID=[0-9][0-9]*/dID=<n>/g' "$1"; }
norm "$WORK/before.txt" > "$WORK/before.norm"
norm "$WORK/after.txt"  > "$WORK/after.norm"
if ! diff -q "$WORK/before.norm" "$WORK/after.norm" > /dev/null; then
    echo "--- what changed across the append ---"
    diff "$WORK/before.norm" "$WORK/after.norm" | head -30
    fail "the append moved the character's resources -- references were not converted"
fi

# 8. A named spot-check, so a dump that silently emptied cannot pass step 7.
for want in '^Name:      Varag the Deathbringer$' '^HP:        42 / 42' 'Race   Orc'; do
    grep -qE "$want" "$WORK/after.txt" ||
        fail "the post-append dump lost its '$want' line"
done

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
echo "PASS: a v1 save written before an Effect was appended to lib/ loaded"
echo "      against the appended module as the identical character, with"
echo "      every array after Effect renumbered underneath it."
exit 0
