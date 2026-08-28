#!/bin/bash
# Regression check for the Unholy Blight sicken effect, inc-tek.8.7 (PA-07-F4).
#
# THE DEFECT. In lib/pspells.irh the Unholy Blight EA_INFLICT segment assigned
# xval TWICE on consecutive tokens -- `xval: ADJUST_CIRC` then `xval: A_AID`.
# The second write overwrote the first, so the applied stati became A_AID (51),
# an UNDEFINED stati, and yval -- the attribute group the ADJUST_CIRC penalty
# acts on -- was never set. The result: a good creature that failed the save
# gained no stati at all and the "sicken good creatures" clause did nothing.
# The second token was meant to be `yval: A_AID`, as the sibling Thornwrack
# effect shows (`xval: ADJUST_CIRC; yval: A_AID`), and the parallel spells
# Order's Wrath and Chaos Hammer each carry a single xval.
#
# THE ORACLE is the Unholy Blight EA_INFLICT segment in the tracked source. It
# is identified without ambiguity by `xval: ADJUST_CIRC; tval: MA_GOOD`, which
# occurs once in the file. This check reads that segment (its opening brace line
# and the token line under it) and demands:
#   - exactly ONE `xval:` in the segment, and it is `xval: ADJUST_CIRC`;
#   - a `yval: A_AID` token is present;
#   - NO `xval: A_AID` token is present (the original double-assignment).
#
# WHY THE ORACLE CANNOT BE FAKED. It reads the shipped data directly, not a
# transient screen. It fails red on the original double-xval and passes only on
# the single-xval / yval:A_AID form.
#
# Exit 0 pass, 1 the defect is present (double xval / no yval), 2 the segment
# could not be found -- the declaration moved or was renamed.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/lib/pspells.irh"

[ -f "$FILE" ] || { echo "FAIL(2): $FILE is missing; nothing was examined"; exit 2; }

# The line number of the segment's opening brace, found by its unique anchor.
ANCHOR="$(grep -nE 'xval:[[:space:]]*ADJUST_CIRC;[[:space:]]*tval:[[:space:]]*MA_GOOD' "$FILE")"
COUNT="$(printf '%s\n' "$ANCHOR" | grep -c .)"
if [ "$COUNT" -ne 1 ]; then
    echo "FAIL(2): expected exactly one Unholy Blight ADJUST_CIRC/MA_GOOD segment, found $COUNT."
    echo "         The declaration moved or was renamed. Re-point this check before trusting it."
    printf '%s\n' "$ANCHOR" | sed 's/^/    | /'
    exit 2
fi

LINE="${ANCHOR%%:*}"
# The segment: its brace line and the two lines that follow, which hold the
# lval/yval/pval tokens and the closing brace.
SEG="$(sed -n "${LINE},$((LINE + 2))p" "$FILE")"

XVAL_N="$(printf '%s\n' "$SEG" | grep -oE 'xval:' | grep -c .)"
HAS_CIRC="$(printf '%s\n' "$SEG" | grep -cE 'xval:[[:space:]]*ADJUST_CIRC')"
HAS_AID_X="$(printf '%s\n' "$SEG" | grep -cE 'xval:[[:space:]]*A_AID')"
HAS_AID_Y="$(printf '%s\n' "$SEG" | grep -cE 'yval:[[:space:]]*A_AID')"

if [ "$XVAL_N" -eq 1 ] && [ "$HAS_CIRC" -eq 1 ] && [ "$HAS_AID_X" -eq 0 ] && [ "$HAS_AID_Y" -ge 1 ]; then
    echo "PASS: Unholy Blight inflict segment carries one xval (ADJUST_CIRC) and yval: A_AID; the sicken applies."
    exit 0
fi

echo "FAIL(1): Unholy Blight inflict segment is malformed (inc-tek.8.7)."
echo "         want: one xval (ADJUST_CIRC), yval: A_AID, no xval: A_AID."
echo "         got: xval count=$XVAL_N, ADJUST_CIRC=$HAS_CIRC, xval:A_AID=$HAS_AID_X, yval:A_AID=$HAS_AID_Y"
printf '%s\n' "$SEG" | sed 's/^/    | /'
exit 1
