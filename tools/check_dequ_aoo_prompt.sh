#!/bin/bash
# gate: live
# An attack of opportunity against an A_DEQU monster must raise the equipment
# confirmation prompt. (bd inc-hy9u, inc-m2zi edit 12)
#
# WHAT IS BEING DEFENDED. Creature::OAttack (src/Fight.cpp) calls
# ConfirmDequAttack(e,EInSlot(SL_WEAPON)) before it resolves the blow. For a
# player with OPT_WARN_DEQU on, taking an AoO against a monster whose A_DEQU
# risks the weapon, that helper asks "Attack the <monster> (". edit 12 is that
# call. Delete it and the AoO strikes without a word; the player loses the
# weapon with no chance to decline.
#
# THE ORACLE is INCURSION_AOO_PROBE, which arms AoOProbeArrange (src/Player.cpp).
# No key script can make a MONSTER provoke an AoO, so the probe finds the first
# hostile A_DEQU monster beside the player and calls ProvokeAoO() on it, which
# offers the player his attack of opportunity. The reproduction script summons
# an acid blob east of an orc warrior wielding an ORDINARY long sword (edit 5
# bypasses hardness for a non-magical item, so its 2d4 acid reaches the prompt).
#
# TWO GUARDS, both required.
#   1. logs/aoo.log must hold a "provoked: " line naming the acid blob. Without
#      it the AoO was never staged. An absent prompt on a run where no AoO
#      happened proves nothing: the assertion below would fail for the wrong
#      reason, and a build that had removed the summoning would read as a
#      regression in OAttack. So a missing provoke line is a FAIL, never a pass.
#   2. the aoo-prompt screen dump must contain "Attack the acid blob (".
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation below
# removes the ConfirmDequAttack call from Creature::OAttack; the prompt then no
# longer appears and guard 2 fails. The mutation is written with the line that
# follows the call so it names the OAttack site exactly once -- the same two
# lines appear again in WAttack (src/Fight.cpp), where they must stay.
#
# Usage: tools/check_dequ_aoo_prompt.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The mutation this check defends: drop the ConfirmDequAttack gate in OAttack,
# so the AoO strikes with no prompt. Declared before the run below so
# --prove-red intercepts here, before the (build-needing) measurement runs.
check_mutation src/Fight.cpp \
'    if (!ConfirmDequAttack(e,EInSlot(SL_WEAPON)))
      return ABORT;

    if (e.EVictim->HasStati(GRABBED,0,e.EActor))' \
'    if (e.EVictim->HasStati(GRABBED,0,e.EActor))'
export INCURSION_AOO_PROBE=1

check_run tools/keys/dequ-aoo-prompt.keys 5

AOO="$CHECK_RUN/logs/aoo.log"
DUMP="$(ls "$CHECK_RUN"/logs/screens/*-aoo-prompt.txt 2>/dev/null | head -1)"

# Guard 1: the probe must have staged an attack of opportunity.
if [ ! -f "$AOO" ]; then
    echo "FAIL: no logs/aoo.log, so no attack of opportunity was staged."
    echo "      The probe (AoOProbeArrange, src/Player.cpp) never fired. An"
    echo "      absent prompt on a run with no AoO proves nothing."
    echo "specimen: $CHECK_RUN"
    exit 1
fi
if ! grep -q '^provoked: .*acid blob' "$AOO"; then
    echo "FAIL: logs/aoo.log holds no provoke line naming the acid blob."
    echo "      The AoO was not staged; see the file:"
    sed 's/^/      /' "$AOO"
    echo "specimen: $AOO"
    exit 1
fi
grep -m1 '^provoked: ' "$AOO"

# Guard 2: the prompt must have been shown on the screen.
if [ ! -f "$DUMP" ]; then
    echo "FAIL: the aoo-prompt dump was never written ($DUMP)."
    echo "specimen: $CHECK_RUN"
    exit 1
fi
if ! grep -qF 'Attack the acid blob (' "$DUMP"; then
    echo "FAIL: the AoO raised no equipment confirmation prompt (inc-m2zi edit 12)"
    echo "      Is the ConfirmDequAttack call still in Creature::OAttack (src/Fight.cpp)?"
    grep -m1 'Attack the' "$DUMP" || echo "      (no 'Attack the' line at all)"
    echo "specimen: $DUMP"
    exit 1
fi
grep -m1 'Attack the acid blob (' "$DUMP" | sed 's/[[:space:]]*|[^|]*$//'

echo "specimen: $AOO"
echo "specimen: $DUMP"
echo "PASS: an attack of opportunity against the acid blob raised the A_DEQU prompt"
exit 0
