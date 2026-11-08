#!/bin/bash
# Decode one save to "<scope path> <field> <kind> <value>" lines, sorted: what each member HOLDS after load.
#
#   tools/pressure/field_values.sh <binary-dir> <save> <out>
#
# <binary-dir> is a built tree (incursion-headless, mod/, lib/). The save is loaded through the real reader by
# -dump, then the real writer re-saves it into a throwaway file in a sandbox, and INCURSION_FIELD_VALUES logs
# every field the writer emitted (src/SaveV1.cpp V1FvRec). Nothing is written outside the sandbox and <out>.
# Exit: 0 <out> written, 2 could not measure (binary missing, load refused, empty result).
set -uo pipefail
[ $# -eq 3 ] || { echo "usage: $0 <binary-dir> <save> <out>" >&2; exit 2; }
BIND="$(cd "$1" && pwd)" || exit 2
SAVE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
OUT="$3"
[ -x "$BIND/incursion-headless" ] || { echo "no $BIND/incursion-headless" >&2; exit 2; }
[ -f "$SAVE" ] || { echo "no save $SAVE" >&2; exit 2; }
SB="$(mktemp -d "${TMPDIR:-/tmp}/incursion-fv.XXXXXX")"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/save" "$SB/logs"
ln -sfn "$BIND/mod" "$SB/mod"
ln -sfn "$BIND/lib" "$SB/lib"
INCURSIONPATH="$SB/" INCURSION_FIELD_VALUES="$SB/fv.txt" "$BIND/incursion-headless" -dump "$SAVE" >"$SB/dump.out" 2>"$SB/dump.err"
st=$?
if [ $st -ne 0 ]; then echo "dump exit $st: $(head -c 300 "$SB/dump.err")" >&2; exit 2; fi
[ -s "$SB/fv.txt" ] || { echo "no field values logged for $SAVE" >&2; exit 2; }
grep -q MALFORMED-RECORD "$SB/fv.txt" && { echo "writer record did not decode for $SAVE" >&2; exit 2; }
LC_ALL=C sort "$SB/fv.txt" > "$OUT"
