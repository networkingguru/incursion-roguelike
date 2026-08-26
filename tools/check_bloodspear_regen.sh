#!/bin/bash
# Regression check for F41 / inc-tek.8.8: the Bloodspear starts regeneration
# at 20 turns per critical-hit damage and extends it at 5 turns per later hit.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
effect="$(awk '
  /^AI_WEAPON Effect "Bloodspear"/ { in_effect = 1 }
  in_effect { print }
  in_effect && /EITEM\(POST\(EV_HIT\)\)/ { in_hit = 1 }
  in_hit && /^[[:space:]]*};[[:space:]]*$/ { exit }
' "$SOURCE")"
compact="$(printf '%s\n' "$effect" | tr '\n' ' ')"

printf '%s\n' "$compact" | grep -Eq 'GainTempStati[[:space:]]*\([[:space:]]*REGEN[[:space:]]*,[[:space:]]*EItem[[:space:]]*,[[:space:]]*min[[:space:]]*\([[:space:]]*amt[[:space:]]*\*[[:space:]]*20[[:space:]]*,[[:space:]]*1000[[:space:]]*\)' || {
    echo "FAIL: Bloodspear's initial REGEN duration must be min(amt*20,1000)."
    exit 1
}
if printf '%s\n' "$compact" | grep -Eq 'GainTempStati[[:space:]]*\([[:space:]]*REGEN[^;]*min[[:space:]]*\([[:space:]]*amt[[:space:]]*\*[[:space:]]*5[[:space:]]*,[[:space:]]*1000[[:space:]]*\)'; then
    echo "FAIL: Bloodspear's old initial min(amt*5,1000) duration remains."
    exit 1
fi
printf '%s\n' "$compact" | grep -Eq 'SetEffStatiDur[[:space:]]*\([[:space:]]*REGEN[^;]*min[[:space:]]*\([[:space:]]*Dur[[:space:]]*\+[[:space:]]*amt[[:space:]]*\*[[:space:]]*5[[:space:]]*,[[:space:]]*1000[[:space:]]*\)' || {
    echo "FAIL: Bloodspear's maxed-rate REGEN path must add amt*5."
    exit 1
}
if printf '%s\n' "$compact" | grep -Eq 'SetEffStatiDur[[:space:]]*\([[:space:]]*REGEN[^;]*min[[:space:]]*\([[:space:]]*Dur[[:space:]]*\+[[:space:]]*amt[[:space:]]*,[[:space:]]*1000[[:space:]]*\)'; then
    echo "FAIL: Bloodspear's bare min(Dur+amt,1000) duration remains."
    exit 1
fi

echo "PASS: F41 / inc-tek.8.8 Bloodspear regeneration durations match its page."
