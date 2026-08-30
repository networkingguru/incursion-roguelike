#!/bin/bash
# Regression check for PA-08-F71 / inc-tek.8.8: the "Staff of Divination"
# (AI_STAFF Effect "Divination" : EA_GRANT) description must name the granted
# spell "true seeing", matching its STAFF_SPELL_LIST grant ($"true seeing") and
# the "True Seeing" spell entity (lib/wspells.irh). No spell named "true sight"
# exists anywhere in lib/; the code wins. Red while the Desc still names the
# phantom "true sight", green once the Desc names "true seeing".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Divination staff block, from its header to the first closing
# "; (the Desc's own close), then test the Desc STRING itself, NOT the whole
# block, so the upstream: comment that quotes the old wording is excluded.
block="$(sed -n '/AI_STAFF Effect "Divination" : EA_GRANT/,/";/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -q "true seeing"; then
    echo "PASS: PA-08-F71 / inc-tek.8.8 the Staff of Divination description names the granted spell \"true seeing\", matching its STAFF_SPELL_LIST grant."
    exit 0
fi

if printf "%s\n" "$desc" | grep -q "true sight"; then
    echo "FAIL: the Staff of Divination description names a phantom spell \"true sight\", yet no spell of that name exists in lib/ and its STAFF_SPELL_LIST grants \"true seeing\"."
    exit 1
fi

echo "FAIL: the Staff of Divination description no longer contains the expected spell-name clause; the anchor or wording changed."
exit 1
