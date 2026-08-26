#!/bin/bash
# Regression check for F42 / inc-tek.8.8: the Bloodspear has bane properties
# against all five races named by its page.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
effect="$(awk '
  /^AI_WEAPON Effect "Bloodspear"/ { in_effect = 1 }
  in_effect && /^AI_WEAPON Effect / && !/"Bloodspear"/ { exit }
  in_effect { print }
' "$SOURCE")"
bane_list="$(printf '%s\n' "$effect" | grep -E '^[[:space:]]*\*[[:space:]]*BANE_LIST([[:space:]]|$)' || true)"

printf '%s\n' "$bane_list" | grep -Eq 'BANE_LIST[[:space:]]+MA_HUMAN[[:space:]]+MA_ELF[[:space:]]+MA_DWARF[[:space:]]+MA_GNOME[[:space:]]+MA_HALFLING[[:space:]]*;' || {
    echo "FAIL: Bloodspear's BANE_LIST must name MA_HUMAN, MA_ELF, MA_DWARF, MA_GNOME and MA_HALFLING in page order."
    exit 1
}

echo "PASS: F42 / inc-tek.8.8 Bloodspear BANE_LIST includes all five races named by its page."
