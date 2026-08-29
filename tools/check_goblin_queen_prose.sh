#!/bin/bash
# Regression check for PA-08-F64 / inc-tek.8.8: the Staff of the Goblin Queen
# (AI_STAFF Effect "the Goblin Queen" : EA_GRANT) description must scope its +4
# Handle Device/Bluff bonuses and its -4 Spot/Listen/Concentration penalties to
# goblinoid wielders, not to a generic "Wielders of the staff". The code wins:
# the EV_MAGIC_HIT handler gates ALL six granted effects behind one
# all-or-nothing goblinoid + 3rd-caster-level test with NO per-effect (e.efNum)
# test, so a non-goblinoid wielder gets none of them -- spells, bonuses and
# penalties alike. The sibling Staff of the Spider uses e.efNum gating, so the
# author had per-effect tooling and deliberately did not use it here; single-tier
# goblinoid scope is the authority and the prose must match it. Red while either
# phrase still reads a bare "Wielders of the staff", green once both read
# "Goblinoid wielders of the staff".
#
# The Desc is line-wrapped, so the target phrases span line breaks; this test
# collapses the Desc's whitespace and newlines to single spaces before matching.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Goblin Queen block, from its header to the first block-closing
# brace, then test the Desc STRING itself, NOT the whole block.
block="$(sed -n '/AI_STAFF Effect "the Goblin Queen" : EA_GRANT/,/^  }/p' "$SOURCE" | sed -n '1,/^  }/p')"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"
# Collapse newlines and runs of whitespace to single spaces so the line-wrapped
# phrases match as one string.
flat="$(printf "%s\n" "$desc" | tr '\n' ' ' | tr -s ' ')"

miss=0

if ! printf "%s\n" "$flat" | grep -q "Goblinoid wielders of the staff also gain"; then
    echo "FAIL: the Staff of the Goblin Queen description does not scope its +4 Handle Device/Bluff bonuses to \"Goblinoid wielders of the staff\"; the bare \"Wielders of the staff also gain\" contradicts the all-or-nothing goblinoid gate that governs every effect."
    miss=1
fi

if ! printf "%s\n" "$flat" | grep -q "Goblinoid wielders of the staff constantly hear"; then
    echo "FAIL: the Staff of the Goblin Queen description does not scope its -4 Spot/Listen/Concentration penalties to \"Goblinoid wielders of the staff\"; the bare \"Wielders of the staff constantly hear\" contradicts the all-or-nothing goblinoid gate that governs every effect."
    miss=1
fi

if [ "$miss" -ne 0 ]; then
    exit 1
fi

echo "PASS: PA-08-F64 / inc-tek.8.8 the Staff of the Goblin Queen description scopes both its +4 bonuses and its -4 penalties to \"Goblinoid wielders\", matching the all-or-nothing goblinoid gate that governs every effect."
