#!/bin/bash
# Regression check for PA-08-F60 / inc-tek.8.8: the ball Wand of Life Stealing
# (the FIRST AI_WAND Effect "Life Stealing" : EA_BLAST, the one whose
# MSG_BLASTNAME is "ball of dark energy") description must state that its
# necromantic damage scales per plus, matching its pval (PLUS_1PER1)d6 code
# under EF_NEEDS_PLUS. The code wins: the damage scales with the wand plus, so
# the Desc must say "per plus". Red while the Desc still reads a flat
# "necromantic damage to", green once it reads "necromantic damage per plus".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the FIRST "Life Stealing" wand block, from its header to the first
# block-closing brace, then test the Desc STRING itself, NOT the whole block.
block="$(sed -n '/AI_WAND Effect "Life Stealing" : EA_BLAST/,/^  }/p' "$SOURCE" | sed -n '1,/^  }/p')"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if ! printf "%s\n" "$desc" | grep -q "necromantic damage per plus"; then
    echo "FAIL: the ball Wand of Life Stealing description does not state its necromantic damage scales \"per plus\", yet its pval (PLUS_1PER1)d6 code scales it with the wand plus."
    exit 1
fi

echo "PASS: PA-08-F60 / inc-tek.8.8 the ball Wand of Life Stealing description states its necromantic damage scales per plus, matching its (PLUS_1PER1)d6 code."
