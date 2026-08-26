#!/bin/bash
# Regression check for F44 / inc-tek.8.8: only an orc wielding the Bloodspear
# receives its +4 saving-throw bonus versus spells.
#
# Structural fallback: scope the oracle to the Bloodspear's wield handler and
# require the orc branch to allow Grant() while the terminal non-orc path skips
# the component grant.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
handler="$(sed -n '/^AI_WEAPON Effect "Bloodspear"/,/EITEM(POST(EV_HIT))/p' "$SOURCE" |
    sed -n '/On Event EITEM(EV_WIELD)/,/^[[:space:]]*},[[:space:]]*$/p')"

printf '%s\n' "$handler" | grep -Eq 'AddQuality\([[:space:]]*WQ_PAIN[[:space:]]*\);[[:space:]]*$' || {
    echo "FAIL: the Bloodspear orc branch no longer adds WQ_PAIN."
    exit 1
}
printf '%s\n' "$handler" | perl -0777 -ne 'exit !/AddQuality\(\s*WQ_PAIN\s*\);\s*return\s+NOTHING\s*;/' || {
    echo "FAIL: the Bloodspear orc branch must return NOTHING after WQ_PAIN."
    exit 1
}
printf '%s\n' "$handler" | perl -0777 -ne 'exit !/return\s+DONE\s*;\s*},\s*$/' || {
    echo "FAIL: the Bloodspear wield handler must end with return DONE."
    exit 1
}
if printf '%s\n' "$handler" | perl -0777 -ne 'exit !/return\s+NOTHING\s*;\s*},\s*$/'; then
    echo "FAIL: the unfixed terminal return NOTHING still grants the +4 to non-orcs."
    exit 1
fi

echo "PASS: F44 / inc-tek.8.8 gates the Bloodspear +4 spell-save bonus to orcs."
