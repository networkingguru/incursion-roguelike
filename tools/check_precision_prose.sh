#!/bin/bash
# Regression check for PA-08-F53 / inc-tek.8.8: the Eyes of Precision
# (AI_EYES Effect "Precision;eyes") description must state that the lowlight
# vision bonus SCALES with the item's magical plus. The CA_LOWLIGHT grant is
# coded pval PLUS_2PER1 with EF_NEEDS_PLUS -- 2 squares per plus, i.e. 20 feet
# per plus at the file's 10-feet-per-square scale -- so the bonus never has a
# fixed value; 20 feet holds only at +1. Red while the lowlight clause states a
# flat "20 feet (2 squares)." with no "per magical plus", green once it scales.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Eyes of Precision entity's first EA_GRANT block (its unique
# header to that block's closing brace), then test the Desc STRING itself
# (Desc: "..." through its closing ";), NOT the whole block: the upstream:
# comment in the block quotes the old flat wording, so a block-wide grep would
# false-match the comment.
block="$(sed -n '/AI_EYES Effect "Precision;eyes" : EA_GRANT/,/}/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"
# Collapse the wrapped Desc to one line so phrases that break across lines match.
flat="$(printf "%s\n" "$desc" | tr '\n' ' ' | tr -s ' ')"

if ! printf "%s\n" "$flat" | grep -qF "per magical plus"; then
    echo "FAIL: the Eyes of Precision description states a flat \"20 feet (2 squares)\" lowlight bonus, not the scaling \"per magical plus\" its CA_LOWLIGHT pval PLUS_2PER1 grants."
    exit 1
fi

echo "PASS: PA-08-F53 / inc-tek.8.8 the Eyes of Precision description states the scaling lowlight bonus (\"per magical plus\")."
