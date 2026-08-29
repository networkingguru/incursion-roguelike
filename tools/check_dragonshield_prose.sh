#!/bin/bash
# Regression check for PA-08-F63 / inc-tek.8.8: the Dragonshield
# (AI_SHIELD Effect "Dragonshield" : EA_BLAST) description must list the dragon
# colour names the shield can actually display, not a colour it never shows. The
# code wins: the displayed name comes from the EV_GETNAME handler, which maps the
# seven damage types to Red (fire), White (cold), Blue (elec), Black (acid),
# Purple (necr), Yellow (slash) and Green (toxi). So "brown" names no shield and
# "yellow" is a real shield name. The Desc must drop "brown" and carry "yellow".
# Red while the Desc colour list still reads "brown", green once it reads
# "yellow". The test targets the Desc STRING only, so the uppercase glyph
# constant BROWN in EV_CALC_EFFECT (case AD_SLASH) is irrelevant to it.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Dragonshield block, from its header to the first block-closing
# brace, then test the Desc STRING itself, NOT the whole block.
block="$(sed -n '/AI_SHIELD Effect "Dragonshield" : EA_BLAST/,/^  }/p' "$SOURCE" | sed -n '1,/^  }/p')"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -q "brown"; then
    echo "FAIL: the Dragonshield description colour list still names \"brown\", a colour its EV_GETNAME handler never displays; the real AD_SLASH shield name is \"Yellow\"."
    exit 1
fi

if ! printf "%s\n" "$desc" | grep -q "yellow"; then
    echo "FAIL: the Dragonshield description colour list omits \"yellow\", the real AD_SLASH shield name its EV_GETNAME handler displays."
    exit 1
fi

echo "PASS: PA-08-F63 / inc-tek.8.8 the Dragonshield description colour list names \"yellow\" and not \"brown\", matching the names its EV_GETNAME handler displays."
