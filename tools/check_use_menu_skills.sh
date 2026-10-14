#!/bin/bash
# gate: live
# The use-skill menu (U) must list only things that work. (bd inc-6sm3)
#
# (a) Appraise, Decipher Script and Escape Artist were in ActiveTraits[]
#     (src/Tables.cpp) but UseSkill has no case for them, so picking one
#     printed "That skill isn't implemented yet." They are passive-only now
#     and must not be listed.
# (b) A polymorphed PC that picked a spit attack hit Error("Unimplemented PC
#     polymorph attack!") because Player::UseMenu's ATTK_VAL switch
#     (src/Skills.cpp) had no A_SPIT case. It must fire: the PC is
#     polymorphed into a spitting spider, spits at an adjacent kobold, and the
#     game prints "Your poison cloud strikes a kobold."
#
# Both parts load tools/fixtures/chars/kobold-rogue-seed1.sav, a rogue with all
# three skills, on seed 1 with the frozen 2026-08-22 settings. A run that
# cannot open the menu, polymorph, or find "Spit Weapon" ends INCONCLUSIVE
# (the key script's @expect), never green.
#
# --prove-red breaks ONE site at a time with tools/check_lib.sh's
# check_mutation (docs/VERIFICATION.md step 2): it requires a green run, applies
# one literal-from/literal-to mutation, rebuilds, re-runs this check, restores
# the source and rebuilds again. There are two mutations and a run proves the
# FIRST one it declares, so USE_MENU_MUTATE=menu|spit (default menu) chooses
# which site is declared first:
#   menu  put SK_DECIPHER back into ActiveTraits[]; the menu must then list
#         Decipher Script, so part (a) goes red.
#   spit  remove the A_SPIT case from the breath group; the polymorph spit then
#         logs "Unimplemented PC polymorph attack!", so part (b) goes red.
#
# Usage: tools/check_use_menu_skills.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/kobold-rogue-seed1.sav
SEED=1

[ -f "$FIXTURE" ] || _check_die 2 "fixture missing: $FIXTURE"
export INCURSION_LOAD="$FIXTURE"

# Two mutation sites, both guarded on every ordinary run. USE_MENU_MUTATE picks
# which one --prove-red reaches (it performs the first mutation declared).
USE_MENU_MUTATE="${USE_MENU_MUTATE:-menu}"
case "$USE_MENU_MUTATE" in
    menu|spit) ;;
    *) _check_die 2 "USE_MENU_MUTATE must be menu or spit, not '$USE_MENU_MUTATE'" ;;
esac

# part (a): the pre-fix ActiveTraits[] listed Decipher Script, which has no
# UseSkill case. Put that line back in front of Disguise.
_mut_menu() {
    check_mutation src/Tables.cpp \
'  SK_DISGUISE + SKILL_VAL,
' \
'  SK_DECIPHER + SKILL_VAL,
  SK_DISGUISE + SKILL_VAL,
'
}
# part (b): the pre-fix breath group had no A_SPIT case, so Player::UseMenu
# Error()ed on a polymorphed spit. Drop the case.
_mut_spit() {
    check_mutation src/Skills.cpp \
'		case A_BRE2:
		case A_SPIT:
' \
'		case A_BRE2:
'
}

if [ "$USE_MENU_MUTATE" = spit ]; then
    _mut_spit
    _mut_menu
else
    _mut_menu
    _mut_spit
fi

# --- (a) the menu ----------------------------------------------------------
echo "(a) the use-skill menu"
check_run tools/keys/use-menu-skills.keys "$SEED"
check_screens '*use-menu'
A_FAIL=0
check_expect "Use which skill, feat or ability?" "the menu opened"
check_expect "Pick Pockets" "a skill that stays listed is on the menu"
for s in "Appraise" "Decipher Script" "Escape Artist"; do
    check_reject "$s" "the menu does not list $s" || A_FAIL=1
done
[ "$CHECK_FAIL" -ne 0 ] && echo "FAIL (a): the use-skill menu lists a skill that has no use (see $CHECK_RUN/logs/screens)"
A_RUN="$CHECK_RUN"; A_STATE=$CHECK_FAIL

# --- (b) the spit ----------------------------------------------------------
CHECK_FAIL=0; CHECK_EXPECTS=0; CHECK_REJECTS=0
echo "(b) polymorph attack: spit"
check_run tools/keys/use-menu-spit.keys "$SEED"
LOG="$CHECK_RUN/logs/errors.log"
UNIMPL=0
[ -f "$LOG" ] && UNIMPL="$(grep -c 'Unimplemented PC polymorph attack' "$LOG")"
echo "  'Unimplemented PC polymorph attack' lines in errors.log: $UNIMPL"
[ "$UNIMPL" -eq 0 ] || { CHECK_FAIL=1; grep -m1 'Unimplemented PC polymorph attack' "$LOG" | sed 's/^/        /'; }
check_screens '*spit-menu'
check_expect "Spit Weapon" "the polymorphed PC's menu lists the spit attack"
check_screens '*spit-fired'
check_expect "Your poison cloud strikes a kobold" "the spit fired and reached the kobold"
[ "$CHECK_FAIL" -ne 0 ] && echo "FAIL (b): the polymorphed PC's spit did not fire (see $CHECK_RUN)"
B_RUN="$CHECK_RUN"; B_STATE=$CHECK_FAIL

echo
if [ "$A_STATE" -ne 0 ] || [ "$B_STATE" -ne 0 ]; then
    echo "FAIL: a=$A_STATE b=$B_STATE (1 = red). specimens: $A_RUN $B_RUN"
    exit 1
fi
echo "PASS: the menu lists no skill without a use, and the polymorphed spit fires"
echo "      specimens: $A_RUN $B_RUN"
exit 0
