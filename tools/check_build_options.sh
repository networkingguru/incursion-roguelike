#!/usr/bin/env bash
# gate: live
#
# Does a build take its options from the file's options: line, and does a walk
# that changed the options on the creation option screen build with the changed
# ones?
#
# WHAT IS BEING PROVED. Spec B11 (bead inc-10v7f, phase 7a). A walk that opens
# the creation option screen and changes an option records `alter_options: yes`
# and writes the changed settings beside the .char as <name>.options.dat; its
# `options:` line names that file. Under the File source the option screen never
# opens (the pick is answered from the file) and the options come from the
# `options:` line alone. Two builds of one recorded walk:
#   1. as recorded: its canonical dump equals the walked character's, outside
#      the allowlist -- the changed option (OPT 104) is in it;
#   2. with the options: line pointing at the unchanged settings file: the
#      dump differs in the Options line, so the line is what the build used.
#
# fact: the character -- a .char recorded now by tools/headless.sh from tools/keys/p6b-alter-options.keys at seed 1 under tools/fixtures/options-2026-08-22.dat (inc-10v7f)
# fact: the changed option -- the one option the key script flips on the option screen; the check reads it only as the presence of `104=1` in the Options line, which the script's own SPACE puts there
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_build_options.sh
# Exit: 0 pass; 1 fail; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
O22=tools/fixtures/options-2026-08-22.dat

W="$(mktemp -d "$ROOT/logs/build-options.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

INCURSION_RECORD_CHAR="$W/alt.char" INCURSION_OPTIONS="$O22" INCURSION_BIN="$BIN" \
    INCURSION_RUN_DIR="$W/walk" tools/headless.sh tools/keys/p6b-alter-options.keys 1 \
    > "$W/walk.log" 2>&1 < /dev/null
[ -f "$W/alt.char" ] && [ -f "$W/alt.options.dat" ] || { echo "INCONCLUSIVE: the recording run left no .char or no .options.dat"; exit 2; }
sav="$(ls "$W"/walk/save/*.sav 2>/dev/null | head -1)"
[ -n "$sav" ] || { echo "INCONCLUSIVE: the walk saved no character"; exit 2; }
INCURSION_OPTIONS="$O22" INCURSION_BIN="$BIN" tools/char_dump.sh "$sav" "$W/walk.canon" > /dev/null 2>&1 || exit 2

fail=0
grep -q '^alter_options: yes' "$W/alt.char" && echo "ok   the recording says alter_options: yes" || { echo "FAIL the recording lacks alter_options: yes"; fail=1; }
grep -q '^options: .*alt\.options\.dat$' "$W/alt.char" && echo "ok   its options: line names alt.options.dat" || { echo "FAIL options: line"; fail=1; }

# 1. As recorded.
if INCURSION_BIN="$BIN" tools/build_fixture.sh "$W/alt.char" "$W/out1" > "$W/b1.log" 2>&1; then
    INCURSION_OPTIONS="$O22" INCURSION_BIN="$BIN" tools/char_dump.sh "$W/out1/alt.sav" "$W/b1.canon" > /dev/null 2>&1
    if tools/canon_compare.py "$W/walk.canon" "$W/b1.canon" > "$W/b1.diff" 2>&1; then
        echo "ok   built from its own .options.dat, the dump equals the walked character's"
    else
        echo "FAIL the dump differs from the walk's:"; head -10 "$W/b1.diff" | cut -c1-180; fail=1
    fi
    grep -q 'Options:.* 104=1' "$W/b1.canon" && echo "ok   the changed option (104=1) is in the built character" || { echo "FAIL 104=1 missing from the built Options line"; fail=1; }
else
    echo "FAIL the recorded .char did not build: $(grep -m1 'BUILD FAILED' "$W/b1.log")"; fail=1
fi

# 2. options: pointing at the unchanged file.
sed "s|^options: .*|options: $O22|" "$W/alt.char" > "$W/alt2.char"
if INCURSION_BIN="$BIN" tools/build_fixture.sh "$W/alt2.char" "$W/out2" > "$W/b2.log" 2>&1; then
    INCURSION_OPTIONS="$O22" INCURSION_BIN="$BIN" tools/char_dump.sh "$W/out2/alt2.sav" "$W/b2.canon" > /dev/null 2>&1
    if tools/canon_compare.py "$W/walk.canon" "$W/b2.canon" > "$W/b2.diff" 2>&1; then
        echo "FAIL the build ignored the options: line (dump equals the walk's)"; fail=1
    elif grep -q 'Options:' "$W/b2.diff"; then
        echo "ok   with the unchanged settings file the Options line differs: the options: line is what the build used"
    else
        echo "FAIL the dumps differ, but not in the Options line:"; head -10 "$W/b2.diff" | cut -c1-180; fail=1
    fi
else
    echo "FAIL the edited .char did not build: $(grep -m1 'BUILD FAILED' "$W/b2.log")"; fail=1
fi

[ $fail -eq 0 ] && { echo "PASS: options come from the options: line (B11)"; exit 0; }
exit 1
