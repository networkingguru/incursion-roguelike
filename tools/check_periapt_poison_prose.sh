#!/bin/bash
# Regression check for PA-08-F55 / inc-tek.8.8: the Periapt of Proof against
# Poisons (AI_AMULET Effect "Periapt of Proof against Poisons") description must
# state that its saving-throw-versus-poison bonus SCALES with the item's magical
# plus. The SN_POISON save is coded pval PLUS_2PER1 (2 per plus) with
# EF_NEEDS_PLUS, so +2 holds only at +1. The toxic-damage-resistance clause is
# already correct ("per magical plus"), so the test anchors on the SAVE clause
# specifically. Red while the save clause still says the flat "a +2 magic bonus
# to saving throws versus poison", green once it says "a +2 per magical plus
# magic bonus".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Periapt entity block, from its unique header to the next
# entity's AI_ header line (the Desc sits in the second EA_GRANT sub-block),
# then test the Desc STRING itself, NOT the whole block: the upstream: comment
# quotes the old flat wording and would false-match a block-wide grep.
block="$(sed -n '/AI_AMULET Effect "Periapt of Proof against Poisons" : EA_GRANT/,/^AI_/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"
# Collapse the wrapped Desc to one line so phrases that break across lines match.
flat="$(printf "%s\n" "$desc" | tr '\n' ' ' | tr -s ' ')"

if printf "%s\n" "$flat" | grep -qF "a +2 magic bonus to saving throws versus poison"; then
    echo "FAIL: the Periapt of Proof against Poisons description still states a flat \"a +2 magic bonus to saving throws versus poison\", contradicting its scaling pval PLUS_2PER1 (2 per plus) save."
    exit 1
fi

if ! printf "%s\n" "$flat" | grep -qF "a +2 per magical plus magic bonus"; then
    echo "FAIL: the Periapt of Proof against Poisons description does not state the scaling \"a +2 per magical plus magic bonus\" saving-throw-versus-poison bonus."
    exit 1
fi

echo "PASS: PA-08-F55 / inc-tek.8.8 the Periapt of Proof against Poisons description states the scaling saving-throw-versus-poison bonus (\"per magical plus\")."
