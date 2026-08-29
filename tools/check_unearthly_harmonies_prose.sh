#!/bin/bash
# Regression check for PA-08-F61 / inc-tek.8.8: the Wand of Unearthly Harmonies
# (AI_WAND Effect "Unearthly Harmonies" : EA_BLAST) description must state that
# its Intelligence damage scales per plus, matching its second EA_BLAST
# xval AD_DAIN / pval (PLUS_1PER1)d2 code under EF_NEEDS_PLUS. The code wins: the
# Intelligence damage scales with the wand plus, so the Desc must say "per plus".
# Red while the Desc still reads the flat "1d2 points of Intelligence damage"
# without a per-plus, green once it reads "1d2 points of Intelligence damage per
# plus". The check tests that specific phrase, so the later "not to the
# Intelligence damage." sentence does not affect the result.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Unearthly Harmonies wand block, from its header to the first
# block-closing brace, then test the Desc STRING itself, NOT the whole block.
block="$(sed -n '/AI_WAND Effect "Unearthly Harmonies" : EA_BLAST/,/^  }/p' "$SOURCE" | sed -n '1,/^  }/p')"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -q "1d2 points of Intelligence damage per plus"; then
    echo "PASS: PA-08-F61 / inc-tek.8.8 the Wand of Unearthly Harmonies description states its Intelligence damage scales per plus, matching its (PLUS_1PER1)d2 code."
    exit 0
fi

if printf "%s\n" "$desc" | grep -q "1d2 points of Intelligence damage"; then
    echo "FAIL: the Wand of Unearthly Harmonies description states a flat \"1d2 points of Intelligence damage\" with no per-plus, yet its second EA_BLAST pval (PLUS_1PER1)d2 code scales it with the wand plus."
    exit 1
fi

echo "FAIL: the Wand of Unearthly Harmonies description no longer contains the expected \"1d2 points of Intelligence damage\" clause; the anchor or wording changed."
exit 1
