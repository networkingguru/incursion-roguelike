#!/bin/bash
# Regression check for PA-08-F77 / inc-tek.8.8: the "Elemental Command (Water)"
# ring description must introduce its staff-spell list as spells "related to
# elemental water", matching the all-water spell list (water walking, part
# water, wall of ice, ice storm, create water, waterspout), not "elemental fire"
# -- a copy-paste from the Fire ring's own introducer. Red while the Water ring
# Desc introducer reads "elemental fire", green once it reads "elemental water".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Water ring block, from its header to the first block-closing
# brace, then test the Desc STRING itself, NOT the whole block, so the
# upstream: comment that quotes the old wording is excluded.
block="$(sed -n '/AI_RING Effect "Elemental Command (Water)" : EA_GRANT/,/^  }/p' "$SOURCE" | sed -n '1,/^  }/p')"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -q "related to elemental water"; then
    echo "PASS: PA-08-F77 / inc-tek.8.8 the Elemental Command (Water) ring description introduces its staff-spells as \"elemental water\"."
    exit 0
fi

if printf "%s\n" "$desc" | grep -q "related to elemental fire"; then
    echo "FAIL: the Elemental Command (Water) ring description introduces its all-water staff-spells as \"elemental fire\", a copy-paste from the Fire ring."
    exit 1
fi

echo "FAIL: the Elemental Command (Water) ring staff-spell introducer is missing; the anchor or wording changed."
exit 1
