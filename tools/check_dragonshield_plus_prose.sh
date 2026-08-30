#!/bin/bash
# Regression check for PA-08-F78 / inc-tek.8.8: the "Dragonshield" description
# must state a "+2 (or higher)" enhancement floor, matching the entity's
# Constants (INITIAL_PLUS +2), which make the shield generate at +2 and never
# below it. The stated "+1 (or higher)" floor is unreachable; the code wins. Red
# while the Desc floor reads "+1 (or higher)", green once it reads "+2 (or
# higher)". The test targets the Desc STRING only, so the upstream: comments
# above the Desc (which quote both the old and new floor) are excluded.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Dragonshield block, from its header to the first block-closing
# brace, then test the Desc STRING itself, NOT the whole block.
block="$(sed -n '/AI_SHIELD Effect "Dragonshield" : EA_BLAST/,/^  }/p' "$SOURCE" | sed -n '1,/^  }/p')"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -q "+2 <7>(or higher)"; then
    echo "PASS: PA-08-F78 / inc-tek.8.8 the Dragonshield description states a \"+2 (or higher)\" floor, matching its INITIAL_PLUS +2 constant."
    exit 0
fi

if printf "%s\n" "$desc" | grep -q "+1 <7>(or higher)"; then
    echo "FAIL: the Dragonshield description states an unreachable \"+1 (or higher)\" floor, yet its Constants set INITIAL_PLUS +2."
    exit 1
fi

echo "FAIL: the Dragonshield enhancement-floor clause is missing; the anchor or wording changed."
exit 1
