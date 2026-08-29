#!/bin/bash
# Regression check for PA-08-F56 / inc-tek.8.8: the Lesser Divine Aspect
# (AI_GIRDLE Effect "Lesser Divine Aspect") description must state that its
# elemental resistances and its disease/poison saves SCALE with the item's
# magical plus. The acid/cold/electricity resistances are coded pval PLUS_5PER1
# (5 per plus) and the disease/poison saves pval PLUS_2PER1 (2 per plus), both
# under EF_NEEDS_PLUS, so resistance 5 and save +2 hold only at +1. (Charisma +4
# and darkvision are genuinely flat.) Red while the Desc still states a flat
# "resistance of 5." with no "per magical plus", green once it scales.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Lesser Divine Aspect entity's first EA_GRANT block (its unique
# header to that block's closing brace, which follows the Desc), then test the
# Desc STRING itself, NOT the whole block: the upstream: comment quotes the old
# flat wording and would false-match a block-wide grep.
block="$(sed -n '/AI_GIRDLE Effect "Lesser Divine Aspect" : EA_GRANT/,/}/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"
# Collapse the wrapped Desc to one line so phrases that break across lines match.
flat="$(printf "%s\n" "$desc" | tr '\n' ' ' | tr -s ' ')"

if ! printf "%s\n" "$flat" | grep -qF "resistance of 5 per magical plus"; then
    echo "FAIL: the Lesser Divine Aspect description states a flat \"resistance of 5.\", not the scaling \"resistance of 5 per magical plus\" its acid/cold/electricity pval PLUS_5PER1 grants."
    exit 1
fi

echo "PASS: PA-08-F56 / inc-tek.8.8 the Lesser Divine Aspect description states the scaling elemental resistance (\"resistance of 5 per magical plus\")."
