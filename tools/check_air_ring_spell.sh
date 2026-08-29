#!/bin/bash
# Regression check for PA-08-F58 / inc-tek.8.8: the "Elemental Command (Air)"
# ring (AI_RING Effect "Elemental Command (Air)") description must name the real
# air spell "gaseous form" in its staff-spell list, not the phantom "wind
# column" that exists nowhere in lib/. The ring code STAFF_SPELL_LIST grants
# "gaseous form" in that first slot, so the code wins. Red while the Desc still
# says "wind column", green once it states "gaseous form".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Air ring entity block from its unique header to the first
# block-closing brace, then test the Desc STRING itself (Desc: "..." through its
# closing ";), NOT the whole block.
block="$(sed -n '/AI_RING Effect "Elemental Command (Air)" : EA_GRANT/,/}/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -Eq "wind column"; then
    echo "FAIL: the Elemental Command (Air) ring description still names the phantom \"wind column\", which exists nowhere in lib/."
    exit 1
fi

if ! printf "%s\n" "$desc" | grep -q "gaseous form"; then
    echo "FAIL: the Elemental Command (Air) ring description does not name the real air spell \"gaseous form\" its STAFF_SPELL_LIST grants."
    exit 1
fi

echo "PASS: PA-08-F58 / inc-tek.8.8 the Elemental Command (Air) ring description names gaseous form, not the phantom wind column."
