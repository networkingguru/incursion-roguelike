#!/bin/bash
# Structural regression check for rule-triage finding F38 / inc-tek.8.8.
# A behavioral check remains the goal; variable combat rolls and hit sequencing
# currently prevent a stable four-target numeric assertion in the headless harness.
#
# Usage: tools/check_sunblade_negative_plane.sh (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

handler="$(sed -n '/On Event EITEM(PRE(EV_HIT)) {/,/On Event EITEM(EV_WIELD) {/p' lib/m_items.irh)"
[ -n "$handler" ] || {
    echo "FAIL: could not find the Sunblade PRE(EV_HIT) handler."
    exit 1
}

fail=0
for required in \
    'EVictim->HasMFlag(M_UNDEAD)' \
    'EVictim->mID == $"spectral mold"' \
    'EVictim->mID == $"mote of negative energy"'; do
    printf '%s\n' "$handler" | grep -qF "$required" || {
        echo "FAIL: Sunblade targeting is missing: $required"
        fail=1
    }
done

[ "$(printf '%s\n' "$handler" | grep -c '^[[:space:]]*e\.vMult++;')" -eq 1 ] || {
    echo "FAIL: Sunblade must apply exactly one live damage multiplier."
    fail=1
}
printf '%s\n' "$handler" | grep -qF 'EVictim->isMType(MA_WRAITH)' && {
    echo "FAIL: the obsolete wraith-only target gate remains."
    fail=1
}
printf '%s\n' "$handler" | grep -Eq 'e\.xDmg[[:space:]]*\+=[[:space:]]*5d6|\+5d6 sunblade' && {
    echo "FAIL: the obsolete +5d6 Sunblade rider remains."
    fail=1
}

if [ "$fail" -eq 0 ]; then
    echo "PASS: Sunblade structurally doubles against undead and both named Negative-Plane exceptions, with no +5d6 rider."
fi
exit "$fail"
