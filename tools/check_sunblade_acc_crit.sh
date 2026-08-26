#!/bin/bash
# Structural regression check for rule-triage finding F40 / inc-tek.8.8.
# The Sunblade must have a bastard sword's Acc +2 and Crit x2 while retaining
# its own damage, threat range, and short-sword speed.
#
# Usage: tools/check_sunblade_acc_crit.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

item="$(sed -n '/^Item "short sword;sunblade" : T_WEAPON$/,/^  }$/p' lib/m_items.irh)"
stat_line="$(printf '%s\n' "$item" | grep -E 'SDmg:[[:space:]]*1d10;[[:space:]]*LDmg:[[:space:]]*1d12;')"

[ -n "$stat_line" ] || {
    echo "FAIL: could not find the Sunblade stat line."
    exit 1
}

fail=0
if ! printf '%s\n' "$stat_line" | grep -Eq 'Acc:[[:space:]]*\+2;.*Crit:[[:space:]]*x2;'; then
    echo "FAIL: the Sunblade must have Acc +2 and Crit x2, matching a bastard sword."
    fail=1
fi
if printf '%s\n' "$stat_line" | grep -Eq 'Acc:[[:space:]]*\+3;|Crit:[[:space:]]*x3;'; then
    echo "FAIL: the old Sunblade Acc +3 or Crit x3 remains."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: F40 / inc-tek.8.8: the Sunblade has a bastard sword's Acc +2 and Crit x2."
fi
exit "$fail"
