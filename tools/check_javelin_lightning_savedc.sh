#!/bin/bash
# Regression check for F47 / inc-tek.8.8: the Javelin of Lightning's Reflex
# save uses the DC promised by its description.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
effect="$(sed -n '/^AI_WEAPON Effect "Lightning;jav"/,/^AI_WEAPON Effect "Sylvan Scimitar"/p' "$SOURCE")"

if printf '%s\n' "$effect" | grep -Fq 'e.vRange = 3 + EActor->Mod(A_DEX)'; then
    echo "FAIL: the Javelin of Lightning still contains the dead Dexterity-based range line."
    exit 1
fi
printf '%s\n' "$effect" | grep -Eq 'e[[:space:]]*\.[[:space:]]*saveDC[[:space:]]*=[[:space:]]*10[[:space:]]*\+[[:space:]]*EActor[[:space:]]*->[[:space:]]*ChallengeRating[[:space:]]*\([[:space:]]*\)[[:space:]]*/[[:space:]]*2[[:space:]]*\+[[:space:]]*EActor[[:space:]]*->[[:space:]]*Mod[[:space:]]*\([[:space:]]*A_DEX[[:space:]]*\)[[:space:]]*;' || {
    echo "FAIL: the Javelin of Lightning does not use the Reflex save DC promised by its description."
    exit 1
}

echo "PASS: F47 / inc-tek.8.8 Javelin of Lightning uses the described Reflex save DC."
