#!/bin/bash
# Regression check for PA-08-F34 / inc-tek.8.8: the Cloak of Shadow Shifting
# requires darkness at both ends and describes its seven daily uses truthfully.
#
# A headless behavioral check is the goal: activate in light and prove the
# refusal spends no charge, then activate in darkness and prove travel reaches
# an unlit destination. Until that scenario exists, this structural falsifier
# requires the source gate to precede charge accounting and requires both the
# random and controlled destination paths to consult Map::LightAt.
#
# Usage: tools/check_shadow_shifting.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0

flag_line="$(grep -n '^#define EF_NEEDS_DARK 106$' inc/Defines.h | cut -d: -f1)"
last_line="$(grep -n '^#define EF_LAST       107$' inc/Defines.h | cut -d: -f1)"
[ -n "$flag_line" ] && [ -n "$last_line" ] || {
    echo "FAIL: EF_NEEDS_DARK 106 or EF_LAST 107 is missing."
    fail=1
}

cloak="$(sed -n '/AI_CLOAK Effect "Shadow Shifting"/,/AI_CLOAK Effect "the Bat"/p' lib/m_items.irh)"
printf '%s\n' "$cloak" | grep -q 'Flags: EF_ACTIVATE, EF_7PERDAY, EF_NEEDS_DARK' || {
    echo "FAIL: Shadow Shifting does not carry EF_NEEDS_DARK with EF_7PERDAY."
    fail=1
}
printf '%s\n' "$cloak" | grep -q 'Seven times per day' || {
    echo "FAIL: the cloak page does not state its seven-use daily limit."
    fail=1
}
printf '%s\n' "$cloak" | grep -q 'from shadow to shadow' || {
    echo "FAIL: the cloak page does not state the shadow-to-shadow travel."
    fail=1
}
printf '%s\n' "$cloak" | grep -q 'TODO: Limit to darkened areas' && {
    echo "FAIL: the obsolete darkness TODO remains."
    fail=1
}

source_gate="$(grep -n 'te->HasFlag(EF_NEEDS_DARK)' src/Magic.cpp | head -1 | cut -d: -f1)"
charge="$(grep -n 'e.EItem->SetCharges(e.EItem->GetCharges()+1)' src/Magic.cpp | head -1 | cut -d: -f1)"
if [ -z "$source_gate" ] || [ -z "$charge" ] || [ "$source_gate" -ge "$charge" ]; then
    echo "FAIL: the source darkness gate is missing or occurs after the daily charge."
    fail=1
fi
sed -n "${source_gate:-1},${charge:-1}p" src/Magic.cpp | grep -q 'LightAt(e.EActor->x, e.EActor->y)' || {
    echo "FAIL: the pre-charge source gate does not consult Map::LightAt."
    fail=1
}

travel="$(sed -n '/EvReturn Magic::Travel(EventInfo &e)/,/^  }/p' src/Effects.cpp)"
[ "$(printf '%s\n' "$travel" | grep -c 'needsDark && m->LightAt(_x,_y)')" -eq 2 ] || {
    echo "FAIL: Travel must reject lit squares in both controlled and random paths."
    fail=1
}
printf '%s\n' "$travel" | grep -q 'bool needsDark = (e.eID && TEFF(e.eID)->HasFlag(EF_NEEDS_DARK))' || {
    echo "FAIL: Travel does not derive the darkness requirement from the effect."
    fail=1
}

if [ "$fail" -eq 0 ]; then
    echo "PASS: the cloak page and both endpoint gates are structurally present."
fi
exit "$fail"
