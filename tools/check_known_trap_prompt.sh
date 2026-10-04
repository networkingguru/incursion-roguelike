#!/bin/bash
# gate: live
# Does the known-trap confirm tell the player the odds? (bd inc-o6xj)
#
# Before the change the prompt read "Confirm move over the <trap>?" and gave no
# number. After it reads "Confirm move over the <trap>? (N% to avoid)", or
# "(cannot be avoided)" for a trap with no save. N is Trap::AvoidChance, which
# reads Creature::SaveChance; tools/check_save_chance.sh proves that number
# against the real SavingThrow. This check proves the prompt SHOWS it, in a real
# session: kobold rogue, a found deathblade scythe trap (level 8, Reflex,
# mundane), seed 3, key script tools/keys/known-trap-prompt.keys.
#
# THE ORACLE is the screen dump of the open prompt. It FAILS when no prompt is
# on screen, and when the prompt lacks the odds. It also checks N against an
# independent figure: 5 * the d20 results r with r == 20 or (r != 1 and
# bonus + r >= DC), DC = 15 + 8 (trap level) for a found trap, bonus = the
# fixture's Reflex save on its character sheet.
#
# Usage: tools/check_known_trap_prompt.sh   (0 pass, 1 fail, 2 could not measure)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/kobold-rogue-seed1.sav
TRAP_LEVEL=8    # lib/, TEffect "deathblade scythe trap"

check_run tools/keys/known-trap-prompt.keys 3
if ! ls "$CHECK_RUN"/logs/screens/*-prompt.txt >/dev/null 2>&1 ||
   ! grep -q 'Confirm move over the' "$CHECK_RUN"/logs/screens/*-prompt.txt; then
    echo "FAIL: no known-trap prompt on any screen of $CHECK_RUN"
    exit 1
fi
check_screens '*-prompt'
check_expect "Confirm move over the" "the prompt is on screen"

line="$(grep -ho 'Confirm move over the[^[]*' "$CHECK_RUN"/logs/screens/*-prompt.txt | head -1)"
echo "  prompt: $line"
case "$line" in
*"% to avoid)"* | *"(cannot be avoided)"*) CHECK_EXPECTS=$((CHECK_EXPECTS + 1)) ;;
*) CHECK_FAIL=1; echo "  FAIL  the prompt shows no odds" ;;
esac

want=4    # the fixture sheet's Reflex: +4 (Rogue +2, Dex +4, encumbrance -2)
n="$(sed -n 's/.*(\([0-9]*\)% to avoid).*/\1/p' <<<"$line")"
if [ -n "$n" ] && [ -n "$want" ]; then
    dc=$((15 + TRAP_LEVEL)); hits=0
    for r in $(seq 1 20); do
        if [ "$r" -eq 20 ] || { [ "$r" -ne 1 ] && [ $((want + r)) -ge "$dc" ]; }; then hits=$((hits + 1)); fi
    done
    if [ "$n" -eq $((hits * 5)) ]; then echo "  ok    N=$n matches bonus $want vs DC $dc"
    else CHECK_FAIL=1; echo "  FAIL  N=$n, expected $((hits * 5)) from bonus $want vs DC $dc"; fi
fi

check_done "the known-trap prompt states the avoid chance"
