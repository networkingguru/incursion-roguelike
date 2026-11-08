#!/bin/bash
# Plant a case's content in a real save and record what the new save holds (inc-cjos0 phase 8, D3).
#
#   tools/pressure/plant.sh <binary-dir> <fixture.sav> <spec> <out.sav> <out-values>
#
# <binary-dir> is a built tree. The fixture is loaded through the real reader by -dump with INCURSION_PLANT=<spec>:
# each spec line (symbolic names only, see src/Dump.cpp "INCURSION_PLANT") is applied through the game's own calls
# and the real writer writes a NEW save at <out.sav>. <out-values> is then tools/pressure/field_values.sh of that
# new save, taken with the SAME build: the baseline a later merged build must keep.
# Exit: 0 written; 2 could not measure (a spec line refused, the writer refused, no change from the input).
#
# fact: the fixture -- a tools/fixtures/chars/*.sav, frozen bytes; no seed, no key script
# fact: the spec -- a case file, symbolic names only; no number names a status, feat, skill or attribute
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 5 ] || { echo "usage: $0 <binary-dir> <fixture.sav> <spec> <out.sav> <out-values>" >&2; exit 2; }
BIND="$(cd "$1" && pwd)" || exit 2
SAVE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
SPEC="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
OUT="$4"; VALS="$5"
[ -x "$BIND/incursion-headless" ] || { echo "no $BIND/incursion-headless" >&2; exit 2; }
[ -f "$SAVE" ] && [ -f "$SPEC" ] || { echo "no fixture or no spec" >&2; exit 2; }
SB="$(mktemp -d "${TMPDIR:-/tmp}/incursion-plant.XXXXXX")"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/save" "$SB/logs"
ln -sfn "$BIND/mod" "$SB/mod"
ln -sfn "$BIND/lib" "$SB/lib"
INCURSIONPATH="$SB/" INCURSION_PLANT="$SPEC" INCURSION_PLANT_OUT="$SB/planted.sav" \
    "$BIND/incursion-headless" -dump "$SAVE" >"$SB/plant.out" 2>"$SB/plant.err"
st=$?
if [ $st -ne 0 ]; then echo "plant exit $st: $(head -c 300 "$SB/plant.err")" >&2; exit 2; fi
[ -s "$SB/planted.sav" ] || { echo "the planter wrote no save" >&2; exit 2; }
cmp -s "$SB/planted.sav" "$SAVE" && { echo "the planted save equals the input" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")" "$(dirname "$VALS")" || exit 2
cp -f "$SB/planted.sav" "$OUT" || exit 2
"$HERE/field_values.sh" "$BIND" "$OUT" "$VALS" || exit 2
