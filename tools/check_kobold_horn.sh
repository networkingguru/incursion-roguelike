#!/bin/bash
# Regression check for PA-08-F66 / inc-tek.8.8: the Horn of the Kobolds
# (AI_HORN Effect "the Kobolds;horn" : EA_SUMMON) promises that a non-kobold
# wielder gets HOSTILE kobolds. The declarative EA_SUMMON path always summoned
# FRIENDLY -- Magic::Summon hardcodes EN_SUMMON with no hostile flag and no race
# check (src/Effects.cpp:1448-1471) -- so the promise needed an On Event
# EV_MAGIC_HIT handler that summons hostile kobolds for a non-kobold wielder and
# returns DONE to suppress the friendly built-in, while a kobold wielder falls
# through (return NOTHING) to the unchanged friendly summon.
#
# This check anchors the "the Kobolds;horn" block and asserts the handler is
# present: the block must test isMType(MA_KOBOLD), summon with EN_HOSTILE, run on
# EV_MAGIC_HIT and return DONE. Red on HEAD (no handler), green on the working
# tree. Behaviour is proved separately by the Observed oracle
# tools/keys/kobold-horn-hostile.keys.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Kobolds-horn block, from its header to the first block-closing
# brace.
block="$(sed -n '/AI_HORN Effect "the Kobolds;horn" : EA_SUMMON/,/^  }/p' "$SOURCE" | sed -n '1,/^  }/p')"

if [ -z "$block" ]; then
    echo "FAIL: could not find the \"the Kobolds;horn\" EA_SUMMON block in $SOURCE."
    exit 1
fi

miss=""
printf "%s\n" "$block" | grep -q "EV_MAGIC_HIT"        || miss="$miss EV_MAGIC_HIT"
printf "%s\n" "$block" | grep -q "isMType(MA_KOBOLD)"  || miss="$miss isMType(MA_KOBOLD)"
printf "%s\n" "$block" | grep -q "EN_HOSTILE"          || miss="$miss EN_HOSTILE"
printf "%s\n" "$block" | grep -q "return DONE"         || miss="$miss return-DONE"

if [ -n "$miss" ]; then
    echo "FAIL: the \"the Kobolds;horn\" block does not make a non-kobold wielder's summon hostile; missing:$miss. The Desc promises hostile kobolds for a non-kobold wielder, but the declarative EA_SUMMON always summons friendly."
    exit 1
fi

echo "PASS: PA-08-F66 / inc-tek.8.8 the \"the Kobolds;horn\" block gates on isMType(MA_KOBOLD) and summons EN_HOSTILE kobolds on EV_MAGIC_HIT (return DONE) for a non-kobold wielder."
