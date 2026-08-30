#!/bin/bash
# Regression check for PA-08-F68 / inc-tek.8.8: the "Sword of the Planes"
# weapon description must scope its +3 enhancement tier to outsiders generally,
# matching its EA_GENERIC EV_WATTACK handler, which grants the +3 to any
# MA_OUTSIDER (else if (EVictim->isMType(MA_OUTSIDER)) newBonus = 3). MA_OUTSIDER
# is broader than "denizens of the ethereal or astral planes" and is the only
# engine type for planar creatures; the code wins. Red while the Desc still
# scopes the +3 tier to "denizens of the ethereal or astral planes", green once
# the +3 tier reads "Against outsiders".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Sword of the Planes weapon block, from its header to the first
# closing "; (the Desc's own close), then test the Desc STRING itself, NOT the
# whole block, so the upstream: comment that quotes the old wording is excluded.
block="$(sed -n '/AI_WEAPON Effect "Sword of the Planes" : EA_GENERIC/,/";/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -q "Against outsiders"; then
    echo "PASS: PA-08-F68 / inc-tek.8.8 the Sword of the Planes description scopes its +3 tier to outsiders generally, matching its MA_OUTSIDER code."
    exit 0
fi

if printf "%s\n" "$desc" | grep -q "denizens of the ethereal"; then
    echo "FAIL: the Sword of the Planes description scopes its +3 tier to \"denizens of the ethereal or astral planes\", yet its EV_WATTACK handler grants the +3 to any MA_OUTSIDER."
    exit 1
fi

echo "FAIL: the Sword of the Planes description no longer contains the expected +3-tier clause; the anchor or wording changed."
exit 1
