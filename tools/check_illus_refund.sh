#!/bin/bash
# Structural regression check for inc-3627.
#
# The defect: Creature::StatiOff refunds illusory (psychosomatic) damage when
# an ILLUS_DMG stati ends, and upstream wrote that refund with max() where min()
# belongs. max() stops at NO LESS THAN the maximum, so a victim who healed
# before the illusion ended keeps s.Mag hit points above mHP, and
# Character::CalcValues preserves the surplus forever. That is how a character
# ends up displayed and saved at 58/56.
#
# This check is structural, not behavioural: driving a real illusion into the
# player needs a wizard-mode key script that summons an illusion and turns it
# hostile, and that script does not exist yet. The A/B measurement that proved
# the defect used an instrumented scratch build; see the bead. A headless
# behavioural check remains the goal.
#
# Usage: tools/check_illus_refund.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

src="src/Status.cpp"
fail=0

[ -f "$src" ] || { echo "FAIL: $src not found."; exit 1; }

# The refund line, whatever its indentation.
line="$(grep -n "cHP + s.Mag" "$src" || true)"

[ -n "$line" ] || {
    echo "FAIL: the ILLUS_DMG refund line has gone from $src."
    echo "      Expected an assignment built from 'cHP + s.Mag'."
    exit 1
}

count="$(printf '%s\n' "$line" | wc -l | tr -d ' ')"
[ "$count" = "1" ] || {
    echo "FAIL: expected exactly one 'cHP + s.Mag' refund site, found $count:"
    printf '%s\n' "$line"
    exit 1
}

case "$line" in
    *"min(cHP + s.Mag, mHP + GetAttr(A_THP))"*) ;;
    *"max("*)
        echo "FAIL: the ILLUS_DMG refund uses max(), which pays above the maximum."
        echo "      $line"
        echo "      It must clamp with min(cHP + s.Mag, mHP + GetAttr(A_THP)). See inc-3627."
        fail=1 ;;
    *)
        echo "FAIL: the ILLUS_DMG refund is no longer the expected clamp."
        echo "      $line"
        echo "      Expected min(cHP + s.Mag, mHP + GetAttr(A_THP)). See inc-3627."
        fail=1 ;;
esac

# The mark the fix carries, so a later edit that drops it is caught here too.
{ grep -q "upstream:" "$src" && grep -q "inc-3627" "$src"; } || {
    echo "FAIL: the inc-3627 'upstream:' mark has gone from $src."
    fail=1
}

if [ "$fail" -eq 0 ]; then
    echo "PASS: the ILLUS_DMG refund clamps to the maximum with min(), and the inc-3627 mark is present."
fi
exit "$fail"
