#!/bin/bash
# gate: live
# A wield that kills the wielder must end the game cleanly. (bd inc-qaav4)
#
# A level 1 Chaotic Good warrior wields the unholy Nine Lives Stealer. Character::Wield calls
# DrainLevels(2), DrainXP throws EV_DEATH, and Explore Mode asks "You die... Die? [yn]". The key
# script answers y. The check then demands what a death in any other place gives:
#   - the session ends without a signal or Fatal() (check_run exits 1 on exit 139 and the like);
#   - death.log records "character died";
#   - errors.log holds no ASSERT.
#
# OBSERVED on the tree with the fix (2026-10-28): after the y, Character::Wield returns into
# Character::Swap, which calls CalcValues; Character::GetInv hits the assert
# '(!h) || (h > 0 && h < 128) || (!Get(h)) || Get(h)->isItem()' (inc/Base.h:883) on a stale item
# handle, and the process dies with SIGSEGV (exit 139). So this check is RED on that tree.
# Without the fix there is no death at all, so no "Die?" prompt: also RED.
#
# fact: character -- fixture alignment-drain-level1 (INCURSION_LOAD): level 1, 0 XP, Chaotic Good
# fact: settings -- options-2026-08-22.dat (CHECK_OPTIONS)
# fact: the weapon and its wrong alignment -- wizard "Item Acquisition", Nine Lives Stealer +2 (fixed unholy)
# fact: monsters -- wizard "Genocide Everything" in the key script
# fact: whether the game asks before killing -- Explore Mode in the fixture; the key script answers y
# fact: the values read -- the dumped "Die?" screen, death.log, errors.log; no dice, no seed
#
# Usage: tools/check_alignment_drain_death.sh   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/alignment-drain-level1.sav
# The mutation removes the isDead() guard in Character::Swap, the one that stops CalcValues
# running on the dead wielder; alone it brings back the ASSERT and exit 139.
check_mutation src/Inv.cpp \
'    if (isDead())
        return true;
' ''

[ -f "$FIXTURE" ] || _check_die 2 "the fixture is missing: $FIXTURE"
export INCURSION_LOAD="$FIXTURE"
check_run tools/keys/alignment-drain-die.keys 1
unset INCURSION_LOAD

check_screens '*die-prompt*'
check_expect "You die... Die? [yn]" "the wield killed the level 1 wielder"

[ -f "$CHECK_RUN/logs/death.log" ] && grep -q "character died" "$CHECK_RUN/logs/death.log" \
    || { echo "FAIL: death.log does not record 'character died' after the y."; CHECK_FAIL=1; }
if grep -q "ASSERT" "$CHECK_RUN/logs/errors.log" 2>/dev/null; then
    echo "FAIL: errors.log holds an ASSERT after the death:"
    grep "ASSERT" "$CHECK_RUN/logs/errors.log" | head -2 | sed 's/^/      /'
    CHECK_FAIL=1
fi

check_done "the level 1 wielder died on the wield and the game ended the death cleanly"
