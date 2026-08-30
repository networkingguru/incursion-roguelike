#!/bin/bash
# Regression check for PA-08-F67 / inc-tek.8.8: the "Circlet of Blasting"
# (AI_HEADBAND Effect "Circlet of Blasting" : EA_BLAST) description must scope
# its base 5d8 damage to living creatures, matching its base EA_BLAST code
# tval: MA_LIVING under EF_LIM_MTYPE (which strikes LIVING creatures only) and
# matching Incursion sibling spell Searing Light (lib/pspells.irh) whose prose
# says "living creatures". The code wins. Red while the Desc still says the base
# tier inflicts "5d8 damage to everything else", green once it says "5d8 damage
# to living creatures".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Circlet of Blasting block, from its header to the first closing
# "; (the Desc's own close), then test the Desc STRING itself, NOT the whole
# block, so the upstream: comment that quotes the old wording is excluded.
block="$(sed -n '/AI_HEADBAND Effect "Circlet of Blasting" : EA_BLAST/,/";/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -q "5d8 damage to living creatures"; then
    echo "PASS: PA-08-F67 / inc-tek.8.8 the Circlet of Blasting description scopes its base 5d8 damage to living creatures, matching its tval: MA_LIVING code."
    exit 0
fi

if printf "%s\n" "$desc" | grep -q "5d8 damage to everything else"; then
    echo "FAIL: the Circlet of Blasting description says its base 5d8 tier hits \"everything else\", yet its base EA_BLAST is coded tval: MA_LIVING and strikes living creatures only."
    exit 1
fi

echo "FAIL: the Circlet of Blasting description no longer contains the expected base 5d8 clause; the anchor or wording changed."
exit 1
