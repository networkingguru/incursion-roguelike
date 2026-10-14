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
# --prove-red restores the pre-fix src/Tables.cpp and src/Skills.cpp from HEAD
# (git show), rebuilds, requires BOTH parts to go red, then puts the fixed
# files back and rebuilds. A trap restores on any exit.
#
# Usage: tools/check_use_menu_skills.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/kobold-rogue-seed1.sav
SEED=1
SRC_FILES="src/Tables.cpp src/Skills.cpp"

[ -f "$FIXTURE" ] || _check_die 2 "fixture missing: $FIXTURE"
export INCURSION_LOAD="$FIXTURE"

# --- --prove-red: mutate to the pre-fix source, run twice, restore. ---------
if [ "$CHECK_PROVE_RED" = 1 ]; then
    keep="$(mktemp -d -t use_menu_prove_red)" || _check_die 2 "no temp directory"
    restored=0
    restore() {
        [ "$restored" = 1 ] && return 0
        local f ok=0
        for f in $SRC_FILES; do
            cp -p "$keep/$(basename "$f")" "$f" && cmp -s "$keep/$(basename "$f")" "$f" || ok=1
        done
        if [ "$ok" = 0 ]; then
            restored=1
            echo "  restored the fixed source; rebuilding"
            BACKEND=posix ./build_macos.sh > "$keep/rebuild.log" 2>&1 ||
                echo "INCONCLUSIVE: rebuild after restore failed, see $keep/rebuild.log" >&2
        else
            echo "INCONCLUSIVE: restore failed; originals are in $keep" >&2
        fi
    }
    trap 'restore' EXIT
    trap 'restore; exit 130' INT TERM HUP

    echo "--- prove red, step 1: the check must be green on the fixed source ---"
    ( CHECK_PROVE_RED=0 "$CHECK_SELF" ) 2>&1 | sed 's/^/  | /'
    [ "${PIPESTATUS[0]}" -eq 0 ] || _check_die 2 "not green to begin with; nothing is proved."

    for f in $SRC_FILES; do cp -p "$f" "$keep/$(basename "$f")" || _check_die 2 "cannot copy $f"; done
    echo "--- prove red, step 2: pre-fix source from HEAD ---"
    for f in $SRC_FILES; do
        git show "HEAD:$f" > "$f" || _check_die 2 "git show HEAD:$f failed"
    done
    git diff --quiet HEAD -- $SRC_FILES || _check_die 2 "source still differs from HEAD after restore-to-HEAD"
    BACKEND=posix ./build_macos.sh > "$keep/mutant-build.log" 2>&1 ||
        _check_die 2 "pre-fix build failed, see $keep/mutant-build.log"
    out="$( ( CHECK_PROVE_RED=0 "$CHECK_SELF" ) 2>&1 )"; inner=$?
    printf '%s\n' "$out" | sed 's/^/  | /'
    restore
    [ "$restored" = 1 ] || exit 2
    [ "$inner" -eq 1 ] || _check_die 2 "pre-fix run exited $inner, wanted 1 (FAIL)"
    printf '%s\n' "$out" | grep -q 'FAIL (a)' || { echo "FAIL: part (a) did not go red on the pre-fix source"; exit 1; }
    printf '%s\n' "$out" | grep -q 'FAIL (b)' || { echo "FAIL: part (b) did not go red on the pre-fix source"; exit 1; }
    echo "PROVED RED: parts (a) and (b) both failed on the pre-fix source; fixed source restored and rebuilt"
    exit 0
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
