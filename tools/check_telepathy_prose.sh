#!/bin/bash
# Regression check for PA-08-F52 / inc-tek.8.8: the "Telepathy" helm (AI_HELM
# Effect "Telepathy") description must state the SCALING telepathy range, not a
# flat "60 feet". The range is coded pval PLUS_ADD5 with EF_NEEDS_PLUS -- plus+5
# squares, i.e. 50 feet + 10 feet per magical plus (Incursion is 10 ft/square),
# so it never has a fixed value; 60 feet holds only at +1. Red while the Desc
# still says the flat "60 feet", green once it states "per magic plus".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the helm entity block from its unique header to the block-closing
# brace, then test the Desc STRING itself (Desc: "..." through its closing ";),
# NOT the whole block: the upstream: comment in the block quotes the old
# "60 feet" wording, so a block-wide grep would false-match the comment.
block="$(sed -n '/AI_HELM Effect "Telepathy" : EA_GRANT/,/}/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -Eq "60 feet"; then
    echo "FAIL: the Telepathy helm description still states the flat \"60 feet\", contradicting its scaling pval PLUS_ADD5 range."
    exit 1
fi

if ! printf "%s\n" "$desc" | grep -q "per magic plus"; then
    echo "FAIL: the Telepathy helm description does not state the scaling \"per magic plus\" range."
    exit 1
fi

echo "PASS: PA-08-F52 / inc-tek.8.8 the Telepathy helm description states the scaling range, not a flat \"60 feet\"."
