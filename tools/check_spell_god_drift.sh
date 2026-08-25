#!/bin/bash
# The drift-rules oracle (docs/SAVE-SCHEMA-SPEC.md, "Drift rules"; phase 5 of
# docs/superpowers/plans/2026-08-25-save-manifest-position-refs.md).
#
# WHAT IT PROVES. A v1 save records each of a module's 21 resource arrays --
# every entry's name, in position order. On load the reader compares that
# record with the module it now has, and REFUSES only on positive evidence
# that entries MOVED. Five module rebuilds, one real save, five verdicts:
#
#   control  an untouched copy of lib/            -> loads
#   insert   one Effect and one God declared in
#            the MIDDLE of their arrays           -> REFUSED (a slide)
#   shuffle  two Gods' names exchanged, so the
#            same names sit at swapped positions  -> REFUSED (a shuffle)
#   rename   one God renamed, nothing moved       -> loads, in silence
#   massrename  EVERY God renamed, nothing moved  -> loads, in silence
#   remove   one Effect and one God deleted       -> REFUSED (a shrink)
#
# The two rename cases are the ones that must NOT refuse. Rule 3 of the
# project's append-only rule says a rename, a replacement, or a mass rename of
# a whole array loads: only movement is a defect. A check that refuses
# everything unfamiliar would pass the three refusals above and still be
# wrong. The mass rename is kept separate because it is where a rule that
# guesses from "how much changed" would go wrong: every compared name differs,
# and it must still load.
#
# THIS REPLACED the name-keyed spell/god persistence oracle of the same name.
# That version proved ordinals could shift without moving state, and used
# INCURSION_V1_INDEXED_RAW to build a deliberately broken position-keyed
# control to contrast with. Position keys are now the design, not the
# control, and the name table it measured no longer exists. Its sandbox
# machinery -- the brace-counting resource remover, the awk insertions and
# the per-module compile -- is kept here; its -schemaload driver is not,
# because a -schematest harness group carries no Game record, and so no
# manifest, and so no drift to detect. Closes bd inc-kh0b, whose REMOVE
# control could not be made green under the old design.
#
# Needs BOTH builds: ./incursion (the developer build carries -compile) for
# the five sandbox modules, and ${INCURSION_BIN:-./incursion-headless} for
# the session and the loads.
#
# Usage: tools/check_spell_god_drift.sh   (exits 0 on pass, 1 on fail)
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-drift.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

REAL_SAVE_BEFORE="$(find "$ROOT/save" -type f 2>/dev/null | sort)"

# --- 1. one real save, written against the repo's own module --------------
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
SAVE_ABS="$(cd "$(dirname "$SAVE")" && pwd)/$(basename "$SAVE")"

# --- 2. the sandbox modules ----------------------------------------------
# Count braces so a nested Effect body is removed as one complete resource
# rather than by a brittle line range.
remove_resource() { # declaration-regexp input output
    local declaration="$1" input="$2" output="$3"
    awk -v declaration="$declaration" '
      !skip && $0 ~ declaration { skip=1; depth=0; opened=0; next }
      skip {
        line=$0
        opens=gsub(/{/, "{", line); closes=gsub(/}/, "}", line)
        if (opens) opened=1
        depth += opens - closes
        if (opened && depth == 0) skip=0
        next
      }
      { print }
    ' "$input" > "$output"
}

new_sandbox() { # name -> echoes the sandbox root
    local name="$1"
    local sb="$WORK/$name"
    mkdir -p "$sb/mod" "$sb/save" "$sb/logs"
    cp -Rf "$ROOT/lib" "$sb/lib"
    ln -sfn "$ROOT/inc" "$sb/inc"
    echo "$sb"
}

compile_sandbox() { # sandbox
    local sb="$1"
    INCURSIONPATH="$sb/" "$COMPILER" -compile main.irc \
        < /dev/null > "$sb/compile.log" 2>&1
    local status=$?
    if [ "$status" -ne 0 ] || [ ! -f "$sb/mod/Incursion.Mod" ]; then
        tail -20 "$sb/compile.log"
        fail "the $(basename "$sb") sandbox module did not compile (exit $status)"
        exit 1
    fi
}

# Each edit is proved in the SOURCE, never by comparing compiled modules:
# the module header carries a build stamp, so two compiles of the identical
# lib/ differ at byte 128 (measured 2026-08-25). cmp would report "the edit
# landed" for an edit that did nothing.
landed() { # description test-result
    [ "$2" = 0 ] || { fail "$1 -- the sandbox edit did not land, so its verdict would prove nothing"; exit 1; }
}

CONTROL="$(new_sandbox control)"
compile_sandbox "$CONTROL"

# insert: one Effect at the front of the Effect array (before the Module
# line, so after only "unimplemented"), one God at the front of the God
# array (before Aiswin, which is the first). Both are the mid-array
# insertion the append-only rule forbids.
INSERT="$(new_sandbox insert)"
awk '
  !done && /^Module "Incursion Core Module"/ {
    print "Effect \"Drift Oracle Effect\" : EA_NOTIMP"
    print "  { Level: 1; }"
    print ""
    done=1
  }
  { print }
' "$INSERT/lib/main.irc" > "$INSERT/lib/main.irc.new" ||
    { fail "Effect insertion failed"; exit 1; }
mv -f "$INSERT/lib/main.irc.new" "$INSERT/lib/main.irc"
awk '
  !done && /^God "Aiswin"$/ {
    print "God \"Drift Oracle God\""
    print "  { }"
    print ""
    done=1
  }
  { print }
' "$INSERT/lib/religion.irh" > "$INSERT/lib/religion.irh.new" ||
    { fail "God insertion failed"; exit 1; }
mv -f "$INSERT/lib/religion.irh.new" "$INSERT/lib/religion.irh"
grep -q '^Effect "Drift Oracle Effect"' "$INSERT/lib/main.irc"
landed "insert: no Drift Oracle Effect in main.irc" $?
grep -q '^God "Drift Oracle God"$' "$INSERT/lib/religion.irh"
landed "insert: no Drift Oracle God in religion.irh" $?
compile_sandbox "$INSERT"

# shuffle: exchange two Gods' names. Only the two declaration lines change,
# so every name a script references still exists and the module compiles;
# what the save sees is the same set of names at two swapped positions,
# which is indistinguishable from moving the declarations and is exactly
# what the shuffle rule is for.
SHUFFLE="$(new_sandbox shuffle)"
awk '
  /^God "Aiswin"$/ { print "God \"Kysul\""; next }
  /^God "Kysul"$/  { print "God \"Aiswin\""; next }
  { print }
' "$SHUFFLE/lib/religion.irh" > "$SHUFFLE/lib/religion.irh.new" ||
    { fail "God swap failed"; exit 1; }
mv -f "$SHUFFLE/lib/religion.irh.new" "$SHUFFLE/lib/religion.irh"
SWAP_FIRST="$(grep -n -E '^God "(Aiswin|Kysul)"$' "$SHUFFLE/lib/religion.irh" | head -1)"
[ "${SWAP_FIRST#*:}" = 'God "Kysul"' ]
landed "shuffle: the first of the two Gods is still $SWAP_FIRST" $?
compile_sandbox "$SHUFFLE"

# rename: one God renamed in place. Aiswin is the deliberate choice -- it is
# declared first and nothing references it, so the rename cannot fail the
# compile for an unrelated reason.
RENAME="$(new_sandbox rename)"
awk '
  /^God "Aiswin"$/ { print "God \"Aiswin the Renamed\""; next }
  { print }
' "$RENAME/lib/religion.irh" > "$RENAME/lib/religion.irh.new" ||
    { fail "God rename failed"; exit 1; }
mv -f "$RENAME/lib/religion.irh.new" "$RENAME/lib/religion.irh"
grep -q '^God "Aiswin the Renamed"$' "$RENAME/lib/religion.irh"
landed "rename: the renamed God is not in religion.irh" $?
! grep -q '^God "Aiswin"$' "$RENAME/lib/religion.irh"
landed "rename: the old God name is still declared" $?
compile_sandbox "$RENAME"

# massrename: every God declaration renamed. Script references to the old
# names go unresolved, which the compiler reports as a warning and not an
# error -- the module still builds, and what this case needs is a module whose
# God array holds the same count in the same order under different names.
MASSRENAME="$(new_sandbox massrename)"
awk '
  /^God "[^"]*"$/ { sub(/"$/, " Renamed\""); print; next }
  { print }
' "$MASSRENAME/lib/religion.irh" > "$MASSRENAME/lib/religion.irh.new" ||
    { fail "God mass rename failed"; exit 1; }
mv -f "$MASSRENAME/lib/religion.irh.new" "$MASSRENAME/lib/religion.irh"
GODS_BEFORE="$(grep -c '^God "' "$CONTROL/lib/religion.irh")"
GODS_RENAMED="$(grep -c '^God ".* Renamed"$' "$MASSRENAME/lib/religion.irh")"
[ "$GODS_BEFORE" -gt 1 ] && [ "$GODS_RENAMED" = "$GODS_BEFORE" ]
landed "massrename: $GODS_RENAMED of $GODS_BEFORE God declarations were renamed" $?
compile_sandbox "$MASSRENAME"

# remove: Aura of Valour is the fixture spell; Aiswin is the unused god.
# Both arrays shrink, which the pre-flight refuses before drift is even
# considered.
REMOVE="$(new_sandbox remove)"
remove_resource '^0 Effect "Aura of Valour"' \
    "$REMOVE/lib/classes.irh" "$REMOVE/lib/classes.irh.new" ||
    { fail "Effect removal failed"; exit 1; }
mv -f "$REMOVE/lib/classes.irh.new" "$REMOVE/lib/classes.irh"
remove_resource '^God "Aiswin"$' \
    "$REMOVE/lib/religion.irh" "$REMOVE/lib/religion.irh.new" ||
    { fail "God removal failed"; exit 1; }
mv -f "$REMOVE/lib/religion.irh.new" "$REMOVE/lib/religion.irh"
! grep -q '^0 Effect "Aura of Valour"' "$REMOVE/lib/classes.irh"
landed "remove: the Effect declaration is still in classes.irh" $?
! grep -q '^God "Aiswin"$' "$REMOVE/lib/religion.irh"
landed "remove: the God declaration is still in religion.irh" $?
compile_sandbox "$REMOVE"

# --- 3. load the ONE save against each module ----------------------------
# Direct INCURSIONPATH invocation: tools/dump_save.sh always symlinks the
# repo's own mod/ in, which would defeat the whole check.
load_against() { # sandbox tag -> exit status; leaves .out and .err
    local sb="$1" tag="$2"
    INCURSIONPATH="$sb/" "$BIN" -dump "$SAVE_ABS" \
        > "$WORK/$tag.out" 2> "$WORK/$tag.err"
    local status=$?
    local leftovers
    leftovers="$(find "$sb/save" "$sb/logs" -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$leftovers" != "0" ]; then
        find "$sb/save" "$sb/logs" -type f
        fail "$tag: -dump wrote $leftovers file(s) into the sandbox; it must be read-only"
    fi
    return $status
}

expect_load() { # sandbox tag label
    local sb="$1" tag="$2" label="$3"
    if ! load_against "$sb" "$tag"; then
        head -5 "$WORK/$tag.err"
        fail "$label: the save was refused, and it must load"
        return 1
    fi
    grep -q '^Format:' "$WORK/$tag.out" ||
        fail "$label: the load exited 0 but produced no dump"
    return 0
}

expect_refusal() { # sandbox tag label needle
    local sb="$1" tag="$2" label="$3" needle="$4"
    if load_against "$sb" "$tag"; then
        fail "$label: the save LOADED against a module it must be refused against"
        return 1
    fi
    if ! grep -qF "$needle" "$WORK/$tag.err"; then
        echo "--- stderr ---"; head -8 "$WORK/$tag.err"
        fail "$label: refused, but stderr never said '$needle'"
        return 1
    fi
    if grep -q '^=== Player' "$WORK/$tag.out"; then
        fail "$label: refused, yet the character report was still printed"
        return 1
    fi
    return 0
}

expect_load "$CONTROL" control "control (untouched module)" &&
    echo "control: the save loads against its own module"

expect_refusal "$INSERT" insert "insert (mid-array Effect and God)" \
    "slid at position" &&
    echo "insert:  REFUSED -- $(grep -o 'incursion: module slot [0-9]* [A-Za-z]* array slid at position [0-9]*' "$WORK/insert.err" | head -1)"

expect_refusal "$SHUFFLE" shuffle "shuffle (two God names exchanged)" \
    "was reordered" &&
    echo "shuffle: REFUSED -- $(grep -o 'incursion: module slot [0-9]* [A-Za-z]* array was reordered' "$WORK/shuffle.err" | head -1)"

expect_refusal "$REMOVE" remove "remove (one Effect and one God deleted)" \
    "array shrank" &&
    echo "remove:  REFUSED -- $(grep -o 'incursion: module slot [0-9]* [A-Za-z]* array shrank' "$WORK/remove.err" | head -1)"

# The rename must load, AND must load to the same character: a rule-3 rename
# moves nothing, so every field of the dump must match the control's apart
# from the header's own Format: line.
if expect_load "$RENAME" rename "rename (one God renamed in place)"; then
    if diff <(grep -v '^Format:' "$WORK/control.out") \
            <(grep -v '^Format:' "$WORK/rename.out") > "$WORK/rename.diff"; then
        echo "rename:  loads, and reads back the identical character"
    else
        head -12 "$WORK/rename.diff"
        fail "rename: loaded, but the character changed -- a rename must move nothing"
    fi
fi

# A mass rename must load too, and must change nothing BUT the names. Undo
# the rename in the text of the dump and the two must then be identical: the
# character still worships the god at the same position, under its new name.
if expect_load "$MASSRENAME" massrename "massrename (every God renamed)"; then
    if diff <(grep -v '^Format:' "$WORK/control.out") \
            <(grep -v '^Format:' "$WORK/massrename.out" | sed 's/ Renamed//g') \
            > "$WORK/massrename.diff"; then
        echo "massrename: all $GODS_RENAMED Gods renamed, loads, character intact"
    else
        head -12 "$WORK/massrename.diff"
        fail "massrename: loaded, but a line with no renamed God in it changed"
    fi
fi

# --- 4. nothing real was touched -----------------------------------------
REAL_SAVE_AFTER="$(find "$ROOT/save" -type f 2>/dev/null | sort)"
[ "$REAL_SAVE_BEFORE" = "$REAL_SAVE_AFTER" ] ||
    fail "the contents of $ROOT/save changed; this check must not touch real saves"

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
echo "PASS: a mid-array insertion, a two-name shuffle and a removal were each"
echo "      refused by name; a single rename and a rename of every God both"
echo "      loaded with the character intact; the untouched module loaded."
