#!/bin/bash
# Regression check for F43 / inc-tek.8.8: the Bloodspear grants its +3
# wounding tier to lizardfolk as promised by its page.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
effect="$(awk '
  /^AI_WEAPON Effect "Bloodspear"/ { in_effect = 1 }
  in_effect && /^AI_WEAPON Effect / && !/"Bloodspear"/ { exit }
  in_effect { print }
' "$SOURCE")"
wield="$(printf '%s\n' "$effect" | sed -n '/On Event EITEM(EV_WIELD)/,/EITEM(POST(EV_HIT))/p')"
compact="$(printf '%s\n' "$wield" | tr '\n' ' ')"

printf '%s\n' "$compact" | grep -Eq 'else[[:space:]]+if[[:space:]]*\([[:space:]]*EActor->isMType[[:space:]]*\([[:space:]]*MA_GOBLINOID[[:space:]]*\)[[:space:]]*\|\|[[:space:]]*EActor->isMType[[:space:]]*\([[:space:]]*MA_TROLL[[:space:]]*\)[[:space:]]*\|\|[[:space:]]*EActor->isMType[[:space:]]*\([[:space:]]*MA_KOBOLD[[:space:]]*\)[[:space:]]*\|\|[[:space:]]*EActor->isMType[[:space:]]*\([[:space:]]*MA_LIZARDFOLK[[:space:]]*\)[[:space:]]*\)[[:space:]]*\{[^}]*SetInherentPlus[[:space:]]*\([[:space:]]*\+3[[:space:]]*\)[[:space:]]*;[^}]*AddQuality[[:space:]]*\([[:space:]]*WQ_WOUNDING[[:space:]]*\)[[:space:]]*;[^}]*AddQuality[[:space:]]*\([[:space:]]*WQ_BANE[[:space:]]*\)' || {
    echo "FAIL: Bloodspear's +3 wounding wielder branch must include MA_GOBLINOID, MA_TROLL, MA_KOBOLD and MA_LIZARDFOLK."
    exit 1
}

echo "PASS: F43 / inc-tek.8.8 Bloodspear +3 wounding tier includes MA_LIZARDFOLK."
