#!/bin/bash
# Regression check for F45 / inc-tek.8.8: the Holy Avenger's on-hit dispel
# uses the wielder's paladin level as its caster level.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
effect="$(sed -n '/^AI_WEAPON Effect "Holy Avenger"/,/^Item /p' "$SOURCE")"

if printf '%s\n' "$effect" | grep -Eq 'e[[:space:]]*\.[[:space:]]*vCasterLev[[:space:]]*=[[:space:]]*12[[:space:]]*;'; then
    echo "FAIL: the Holy Avenger dispel still uses hardcoded caster level 12."
    exit 1
fi
printf '%s\n' "$effect" | grep -Eq 'e[[:space:]]*\.[[:space:]]*vCasterLev[[:space:]]*=[[:space:]]*EActor[[:space:]]*->[[:space:]]*LevelAs[[:space:]]*\([[:space:]]*\$"paladin"[[:space:]]*\)[[:space:]]*;' || {
    echo "FAIL: the Holy Avenger dispel does not use the wielder's paladin level."
    exit 1
}

echo "PASS: F45 / inc-tek.8.8 Holy Avenger dispel uses the wielder's paladin level."
