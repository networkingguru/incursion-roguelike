#!/bin/bash
# gate: live
# Restoring drained XP must not pay it back twice. (bd inc-3gli)
#
# THE DEFECT. XP and XP_Drained are separate counters (inc/Creature.h).
# Effective XP is TotalXP() - XPDrained(), recomputed at the status line
# (src/Term.cpp), the character sheet (src/Sheet.cpp), advancement
# (src/Managers.cpp) and crafting (src/Skills.cpp). Character::DrainXP
# (src/Create.cpp) only does XP_Drained += amt; it never touches XP.
# Creature::RestoreXP used to both clear XP_Drained by the restored amount
# AND credit that same amount onto XP, so draining 500 and then restoring it
# left effective XP 500 ABOVE where it started -- energy drain became a net
# XP gain. src/Player.cpp calls RestoreXP on every rest, so this was
# routine, not exotic.
#
# THE ORACLE is INCURSION_XPDRAIN_PROBE, which arms Character::XPDrainProbe()
# (src/Create.cpp), run once at the top of Game::Play() on the live player.
# It grants 10000 XP to clear any drain, records effective XP, drains 500,
# records again, restores 500, records a third time, and narrates all three
# through Error() as one line, "XPDRAIN_PROBE e0=<n> e1=<n> e2=<n>", because
# errors.log is the channel under test -- the same pattern
# check_quiet_lookup.sh uses.
#
# TWO PROPERTIES, read off that one line:
#
#   e1 == e0 - 500   the drain is visible
#   e2 == e0         the restore returns exactly what was taken, no more
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation
# below restores the second, double-paying credit RestoreXP used to add
# beside clearing the drain. The probe then logs e2 == e0 + 500, which this
# check reports as a violation and exits 1.
#
# Usage: tools/check_xp_drain.sh [--prove-red]   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

SEED=3
KEYS=tools/keys/dive.keys

# The mutation this check defends: restore the second, double-paying credit
# Creature::RestoreXP used to add right after clearing XP_Drained. Declared
# before the run below so --prove-red intercepts here, before the
# (build-needing) measurement ever runs once in this process at all.
check_mutation inc/Creature.h \
'          XP_Drained -= xp;' \
'          XP_Drained -= xp;
          XP += xp;'

export INCURSION_XPDRAIN_PROBE=1

check_run "$KEYS" "$SEED"

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 \
    "the run logged nothing at all. The probe reports through Error()," \
    "so an empty log means it never ran."

# Drop the indented backtrace blocks headless.sh attaches to a first
# occurrence; they quote the message text and would be counted twice.
LINE="$(grep -v '^    ' "$LOG" | grep 'XPDRAIN_PROBE ' | head -1)"
[ -n "$LINE" ] || _check_die 2 \
    "the probe never ran. Is Character::XPDrainProbe() still called from" \
    "Game::Play(), and does this build contain it?"

E0="$(echo "$LINE" | grep -oE 'e0=-?[0-9]+' | sed 's/e0=//')"
E1="$(echo "$LINE" | grep -oE 'e1=-?[0-9]+' | sed 's/e1=//')"
E2="$(echo "$LINE" | grep -oE 'e2=-?[0-9]+' | sed 's/e2=//')"

[ -n "$E0" ] && [ -n "$E1" ] && [ -n "$E2" ] || _check_die 2 \
    "could not parse e0/e1/e2 out of the probe line:" \
    "  $LINE"

FAIL=0

if [ "$E1" -ne $((E0 - 500)) ]; then
    echo "FAIL: draining 500 XP did not lower effective XP by 500."
    echo "      e0=$E0 e1=$E1 (wanted e1 == e0-500 == $((E0 - 500)))"
    FAIL=1
fi

if [ "$E2" -ne "$E0" ]; then
    echo "FAIL: restoring the drained 500 XP did not return exactly to e0."
    echo "      e0=$E0 e2=$E2 (wanted e2 == e0 == $E0)"
    if [ "$E2" -eq $((E0 + 500)) ]; then
        echo "      e2 is e0+500: RestoreXP paid the drained amount back TWICE."
    fi
    FAIL=1
fi

echo
echo "--- what the probe logged ---"
echo "$LINE"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

echo
echo "PASS: seed $SEED -- e0=$E0 e1=$E1 e2=$E2. Draining 500 XP lowered"
echo "      effective XP by exactly 500, and restoring it returned exactly"
echo "      to e0, with no double payment."
exit 0
