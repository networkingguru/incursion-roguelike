#!/usr/bin/env bash
# gate: live
#
# Does a built character depend on the seed: line?
#
# WHAT IS BEING PROVED. Spec V3 (bead inc-10v7f, phase 7a): the `seed:` line
# seeds only what the file does not state, so two builds of one .char under two
# seeds MUST give the same character. Each recorded character below is built
# under 8 seeds; the canonical dump of every build MUST equal the first one's
# outside the one allowlist in tools/canon_compare.py.
#
# The two characters: the default orc barbarian (a perk wand, whose charges the
# file states) and the Drow ranger that stops at creation (a gear line "of
# random 3 to 4"). Both are recorded now, by a normal run.
#
# fact: the character -- a .char recorded now by tools/headless.sh from tools/keys/chargen-default-save.keys (seed 1, tools/fixtures/options-2026-08-22.dat) and from tools/keys/p7a-drow-ranger-save.keys (seed 1, tools/fixtures/options-2026-08-22-noautohide.dat) (inc-10v7f)
# fact: the seed -- the `seed:` line of the .char, set by this script to 8 values; every other INCURSION_* variable is removed by tools/build_fixture.sh
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_build_seeds.sh
# Exit: 0 all 8 builds of both characters agree; 1 two differ; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
SEEDS="${CHECK_BUILD_SEEDS:-1 2 3 17 99 4242 31337 20261107}"

W="$(mktemp -d "$ROOT/logs/build-seeds.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

fail=0
one() {   # <name> <keys> <options>
    local name="$1" keys="$2" opts="$3" first="" s
    INCURSION_RECORD_CHAR="$W/$name.char" INCURSION_OPTIONS="$opts" INCURSION_BIN="$BIN" \
        INCURSION_RUN_DIR="$W/$name-walk" tools/headless.sh "$keys" 1 > "$W/$name-walk.log" 2>&1 < /dev/null
    [ -f "$W/$name.char" ] || { echo "INCONCLUSIVE: no .char for $name"; exit 2; }
    for s in $SEEDS; do
        sed "s/^seed: .*/seed: $s/" "$W/$name.char" > "$W/$name-s$s.char"
        if ! INCURSION_BIN="$BIN" tools/build_fixture.sh "$W/$name-s$s.char" "$W/out-$name-$s" > "$W/$name-s$s.log" 2>&1; then
            echo "FAIL $name seed $s: $(grep -m1 'BUILD FAILED' "$W/$name-s$s.log" || tail -1 "$W/$name-s$s.log")"; fail=1; continue
        fi
        INCURSION_OPTIONS="$opts" INCURSION_BIN="$BIN" tools/char_dump.sh "$W/out-$name-$s/$name-s$s.sav" "$W/$name-s$s.canon" > /dev/null 2>&1 \
            || { echo "FAIL $name seed $s: the dump failed"; fail=1; continue; }
        if [ -z "$first" ]; then
            first="$W/$name-s$s.canon"
            echo "ok   $name seed $s (reference)"
        elif tools/canon_compare.py "$first" "$W/$name-s$s.canon" > "$W/$name-s$s.diff" 2>&1; then
            echo "ok   $name seed $s equals the reference"
        else
            echo "FAIL $name seed $s differs from the reference:"; head -12 "$W/$name-s$s.diff" | cut -c1-180; fail=1
        fi
    done
}

one orc-barbarian tools/keys/chargen-default-save.keys tools/fixtures/options-2026-08-22.dat
one drow-ranger   tools/keys/p7a-drow-ranger-save.keys tools/fixtures/options-2026-08-22-noautohide.dat

[ $fail -eq 0 ] && { echo "PASS: both characters build the same under 8 seeds"; exit 0; }
exit 1
