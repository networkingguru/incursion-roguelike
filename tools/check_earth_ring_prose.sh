#!/bin/bash
# Regression check for PA-08-F76 / inc-tek.8.8: the "Elemental Command (Earth)"
# ring description must name the wearer's own ring "the ring of earth" in its
# curse clause, not "the ring of air" -- a copy-paste from the Air ring. The
# entity is the Earth ring: it tests isMType(MA_EARTH), commands earth creatures
# and grants earth staff-spells, so the NAME is the error; the -4 penalty versus
# petrification is the earth ring's own correct curse. Red while the Earth ring
# Desc curse clause reads "ring of air", green once it reads "ring of earth".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Earth ring block, from its header to the first block-closing
# brace, then test the Desc STRING itself, NOT the whole block, so the
# upstream: comment that quotes the old wording is excluded.
block="$(sed -n '/AI_RING Effect "Elemental Command (Earth)" : EA_GRANT/,/^  }/p' "$SOURCE" | sed -n '1,/^  }/p')"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -q "bearer of the ring of earth"; then
    echo "PASS: PA-08-F76 / inc-tek.8.8 the Elemental Command (Earth) ring description names its curse clause \"the ring of earth\"."
    exit 0
fi

if printf "%s\n" "$desc" | grep -q "bearer of the ring of air"; then
    echo "FAIL: the Elemental Command (Earth) ring description names its curse clause \"the ring of air\", a copy-paste from the Air ring; the entity is the Earth ring."
    exit 1
fi

echo "FAIL: the Elemental Command (Earth) ring curse clause is missing; the anchor or wording changed."
exit 1
