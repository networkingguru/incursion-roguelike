#!/bin/bash
# Regression check for the Divine Power STR-18 feat grant, inc-tek.8.7 / PA-07-F6.
#
# THE DEFECT. The Divine Power spell's POST(EV_MAGIC_HIT) handler in
# lib/pspells.irh has two STR-18 branches, and the spell's own Desc promises they
# reward differently:
#   - STR 18 and you DO NOT already have Power Attack -> you GAIN the Power
#     Attack feat (FT_POWER_ATTACK);
#   - STR 18 and you ALREADY have Power Attack -> you gain Knock Prone
#     (FT_KNOCK_PRONE) instead.
# Both branches granted FT_KNOCK_PRONE, a copy-paste slip, so the "gain Power
# Attack" case never fired. The fix grants FT_POWER_ATTACK in the second branch.
#
# THE TWO ORACLES, read straight from the tracked source so no transient screen
# can fake them, and BOTH asserted so a regression on either side fails red:
#   1. The branch guarded by `&& HasFeat(FT_POWER_ATTACK)` (you already have the
#      feat) MUST still grant FT_KNOCK_PRONE.
#   2. The bare `else if (... A_STR ... >= 18)` branch (you do not have the feat)
#      MUST grant FT_POWER_ATTACK.
# A blind search-and-replace that touched branch 1 fails oracle 1; the pre-fix
# duplicate fails oracle 2.
#
# Exit 0 both branches correct, 1 a branch grants the wrong feat, 2 the handler
# or a branch could not be found (the declaration moved or was renamed).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/lib/pspells.irh"

[ -f "$FILE" ] || { echo "FAIL(2): $FILE is missing; nothing was examined"; exit 2; }

# Branch 1: the STR>=18 AND HasFeat(FT_POWER_ATTACK) guard. Read the feat token
# on the GainTempStati line that follows it (the "Divine Power" source anchors us
# in this handler and not some other GainTempStati).
B1="$(grep -A2 'IAttr(A_STR) >= 18 && EActor->HasFeat(FT_POWER_ATTACK)' "$FILE" \
        | grep -B0 -A0 'Divine Power')"
B1_FEAT="$(printf '%s\n' "$B1" | grep -oE 'FT_[A-Z_]+' | head -1)"

# Branch 2: the bare STR>=18 else-if (no HasFeat test on the same line).
B2="$(grep -A2 'else if (EActor->IAttr(A_STR) >= 18)' "$FILE" \
        | grep 'Divine Power')"
B2_FEAT="$(printf '%s\n' "$B2" | grep -oE 'FT_[A-Z_]+' | head -1)"

if [ -z "$B1_FEAT" ] || [ -z "$B2_FEAT" ]; then
    echo "FAIL(2): could not locate both Divine Power STR-18 branches."
    echo "         branch1 feat='${B1_FEAT:-<none>}' branch2 feat='${B2_FEAT:-<none>}'"
    echo "         The handler moved or was renamed. Re-point this check first."
    exit 2
fi

ok=1
if [ "$B1_FEAT" != "FT_KNOCK_PRONE" ]; then
    echo "FAIL(1): the HasFeat(FT_POWER_ATTACK) branch grants $B1_FEAT, not FT_KNOCK_PRONE."
    echo "         A search-and-replace likely corrupted branch 1."
    ok=0
fi
if [ "$B2_FEAT" != "FT_POWER_ATTACK" ]; then
    echo "FAIL(1): the bare STR-18 branch grants $B2_FEAT, not the FT_POWER_ATTACK the Desc promises."
    echo "         Fix the feat token in lib/pspells.irh (inc-tek.8.7 / PA-07-F6)."
    ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "PASS: Divine Power grants FT_POWER_ATTACK when STR 18 and no Power Attack,"
    echo "      and FT_KNOCK_PRONE when STR 18 and Power Attack already held."
    exit 0
fi
exit 1
