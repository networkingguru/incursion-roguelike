#!/bin/bash
# Regression check for PA-08-F54 / inc-tek.8.8: the Cowl of Warding
# (AI_HEADBAND Effect "Cowl of Warding") description must state that its
# save-versus-spells and armour-luck bonuses SCALE with the item's magical plus.
# The SN_SPELLS save is coded pval PLUS_ADD3 (plus+3) and the A_ARM luck bonus
# pval PLUS_ADD5 (plus+5), both additive with the plus under EF_NEEDS_PLUS, so
# +4 / +6 hold only at +1. Red while the Desc still claims a flat
# "a +4 bonus to save versus spells", green once it states "+3 plus its magical
# plus".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Cowl entity block, from its unique header to the next entity's
# AI_ header line (the Desc sits in the entity's LAST EA_GRANT sub-block, past
# several closing braces), then test the Desc STRING itself, NOT the whole
# block: the upstream: comment quotes the old flat wording and would false-match
# a block-wide grep.
block="$(sed -n '/AI_HEADBAND Effect "Cowl of Warding" : EA_GRANT/,/^AI_/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"
# Collapse the wrapped Desc to one line so phrases that break across lines match.
flat="$(printf "%s\n" "$desc" | tr '\n' ' ' | tr -s ' ')"

if printf "%s\n" "$flat" | grep -qF "a +4 bonus to save versus spells"; then
    echo "FAIL: the Cowl of Warding description still states a flat \"a +4 bonus to save versus spells\", contradicting its additive pval PLUS_ADD3 (plus+3) save."
    exit 1
fi

if ! printf "%s\n" "$flat" | grep -qF "+3 plus its magical plus"; then
    echo "FAIL: the Cowl of Warding description does not state the scaling \"+3 plus its magical plus\" save-versus-spells bonus."
    exit 1
fi

echo "PASS: PA-08-F54 / inc-tek.8.8 the Cowl of Warding description states the scaling save-versus-spells bonus (\"+3 plus its magical plus\")."
