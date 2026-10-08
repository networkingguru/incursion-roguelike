#!/bin/bash
# gate: cheap
# Regression check for inc-paq9: Druid "Wall of Thorns" description must state the
# 30-foot (3-square) diameter its lval: 2 globe actually fills, not the 50-foot
# (5-square) one it used to advertise. Magic::AGlobe fills each square with
# dist(cx,cy,x,y) < e.vRadius, and vRadius is lval (2), so the wall is 3x3.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/pspells.irh}"
# Anchor on the effect header followed immediately by its "{ SC_ARC" line so the
# commented-out list entry of the same name is not matched; the `want` flag is
# set only by the header and cleared on the very next line unless that line is
# the brace, so header and brace must be adjacent. Extraction ends after the
# first printed line whose closing brace sits at end of line (covers both the
# one-line `"; }` and a lone `  }`).
block="$(awk '
  want && /^  \{ SC_ARC/ { start=1 }
  want && !/^  \{ SC_ARC/ { want=0 }
  start { print; if (/\}[[:space:]]*$/) exit }
  /^Druid Spell "Wall of Thorns" : EA_TERRAFORM$/ { want=1 }
' "$SOURCE")"

if [ -z "$block" ]; then
    echo "FAIL: could not find the Wall of Thorns EA_TERRAFORM block."
    exit 1
fi

if grep -Fq '50 feet (5 squares)' <<< "$block"; then
    echo "FAIL: Wall of Thorns description still advertises the 50-foot (5-square) diameter."
    exit 1
fi

if ! grep -Fq '30 feet (3 squares)' <<< "$block"; then
    echo "FAIL: Wall of Thorns description does not state the 30-foot (3-square) diameter."
    exit 1
fi

if ! grep -Fq 'lval: 2;' <<< "$block"; then
    echo "FAIL: Wall of Thorns block no longer has lval: 2 (the script must stay)."
    exit 1
fi

echo "PASS: inc-paq9 Wall of Thorns description states the 30-foot (3-square) diameter its lval: 2 globe fills."
