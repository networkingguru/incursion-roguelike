#!/bin/bash
# gate: live
# Does eating a sapient corpse charge the right alignment axis? (bd inc-08js)
#
# THE RULE UNDER TEST. Eating a sapient corpse charges alignment at two
# moments: the first bite (src/Item.cpp, Food::Eat) and the finish
# (src/Skills.cpp, Creature::DevourMonster). At each moment:
#   - the act is non-lawful unless the eater is orc, kobold, lizardfolk
#     (MA_REPTILE) or drow;
#   - the act is non-good when the corpse is the eater's own race
#     (Creature::isSameRaceAs, src/Values.cpp).
#
# FOUR CASES, one headless session each (tools/keys/cannibal-*.keys). Every
# eater is a Lawful Good paladin, because Character::AlignedAct (src/Prayer.cpp)
# lets AL_NONGOOD move only a Good character and AL_NONLAWFUL only a Lawful
# one: a neutral eater would show no movement for any case and prove nothing.
#
#   case  eater  corpse     law/chaos       good/evil
#   ----  -----  ---------  --------------  ----------------
#   1     human  human      moves (chaos)   moves (evil)
#   2     human  dwarf      moves (chaos)   does NOT move
#   3     orc    cave orc   does NOT move   moves (evil)
#   4     orc    human      does NOT move   does NOT move
#
# THE ORACLE is the game's own character dump (the sheet's "Spiritual State"
# lines, src/Sheet.cpp), written with the sheet's [W]rite Dump before and after
# the meal in the SAME session. The dump states each axis as a strength phrase
# ("decisively Good", "nominally Lawful"), one phrase per 4 points of score.
# The check ranks the phrases, signs them (Good/Lawful negative, Evil/Chaotic
# positive) and compares before to after. "Moves" means the signed rank rose
# (toward evil / chaos); "does not move" means it is identical.
#
# Measured on seed 4 (the two scores are inferred from the phrase, which names
# a 4-point band; both axes start at -50 on a fresh Lawful Good character):
#   case  law/chaos before -> after        good/evil before -> after
#   1     decisively Lawful -> nominally   decisively Good -> very strong Good
#   2     decisively Lawful -> nominally   decisively Good -> decisively Good
#   3     decisively Lawful -> decisively  decisively Good -> very strong Good
#   4     decisively Lawful -> decisively  decisively Good -> decisively Good
# These match the arithmetic of AlignedAct's committed branch, which scales the
# score by (10 - magnitude) / 10: law/chaos 2 then 3 (-50 -> -40 -> -28),
# good/evil 5 then 3 (-50 -> -25 -> -17, the second charge landing only because
# -25 is still Good).
#
# LIMIT. A band is 4 points wide, so "does not move" cannot see a change of
# under 4 points inside one band. Every charge here is 15 points or more, so a
# leak of the same size moves the phrase. Only the total of both moments is
# read; the first bite and the finish are not separated.
#
# THE KILL is the wizard menu's Genocide Everything, not a melee kill: a
# paladin who attacks a summoned creature takes alignment penalties and god
# messages of his own, which would sit inside the "before" reading.
#
# A RUN THAT MEASURED NOTHING is INCONCLUSIVE (exit 2), not a pass: case 4 and
# the "does not move" halves would otherwise pass on a session that never ate.
# The message log must say the meal finished, and both dumps must exist.
#
# Usage: tools/check_cannibal_alignment.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=4
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"
HUMAN=tools/fixtures/chars/human-paladin-seed4-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$HUMAN" ] || {
    echo "INCONCLUSIVE: no fixture $HUMAN"
    exit 2
}

# run_case <name> <corpse> [load]  -> sets RUN to the run directory
run_case() {
    local name="$1" load="${3:-}" out
    if [ -n "$load" ]; then
        out="$(INCURSION_LOAD="$load" INCURSION_OPTIONS="$OPTIONS" \
               tools/headless.sh "tools/keys/cannibal-$name.keys" "$SEED" 2>&1 </dev/null)"
    else
        out="$(INCURSION_OPTIONS="$OPTIONS" \
               tools/headless.sh "tools/keys/cannibal-$name.keys" "$SEED" 2>&1 </dev/null)"
    fi
    RUN="$(echo "$out" | awk '/^run:/ {print $2}')"
    if [ -z "$RUN" ] || grep -qE 'NO GAMEPLAY|the key script looked for something' <<<"$out"; then
        echo "INCONCLUSIVE: case $name did not complete its measurement."
        echo "$out" | tail -15
        exit 2
    fi
    for f in "$RUN/logs/$name-pre.txt" "$RUN/logs/$name-post.txt"; do
        [ -s "$f" ] || { echo "INCONCLUSIVE: case $name wrote no $f. Run dir: $RUN"; exit 2; }
    done
    if ! grep -qF "You finish eating the $2 corpse" "$RUN"/logs/screens/*-log-"$name".txt 2>/dev/null; then
        echo "INCONCLUSIVE: case $name: the message log never says the $2 corpse was eaten."
        echo "              Run dir: $RUN"
        exit 2
    fi
}

# axis <dump> <good-evil|law-chaos> -> signed rank. Good/Lawful negative,
# Evil/Chaotic positive, "perfectly neutral" 0. Empty when no phrase is found.
axis() {
    local block words phrase rank sign
    block="$(sed -n '/^Spiritual State/,/^CharGen Options/p' "$1" | tr '\n' ' ' | sed 's/_//g; s/  */ /g')"
    if [ "$2" = good-evil ]; then
        words='Good|Evil'
    else
        words='Lawful|Chaotic|Law|Chaos'
    fi
    phrase="$(echo "$block" | grep -oE "You (are|have|flawlessly embody) [a-z ]*($words)" | head -1)"
    [ -n "$phrase" ] || return 0
    case "$phrase" in
        *"perfectly neutral"*) echo 0; return ;;
        *"flawlessly embody"*) rank=11 ;;
        *zealously*)           rank=10 ;;
        *devotedly*)           rank=9 ;;
        *decisively*)          rank=8 ;;
        *moderately*)          rank=7 ;;
        *nominally*)           rank=6 ;;
        *haltingly*)           rank=5 ;;
        *"very strong"*)       rank=4 ;;
        *strong*)              rank=3 ;;
        *slight*)              rank=1 ;;
        *tendancies*|*"You have "*) rank=2 ;;
        *) return 0 ;;
    esac
    case "$phrase" in
        *Evil|*Chaotic|*Chaos) sign=1 ;;
        *)                     sign=-1 ;;
    esac
    echo $((sign * rank))
}

fail=0
# verdict <case> <axis-name> <before> <after> <moves|still>
verdict() {
    local c="$1" a="$2" b="$3" e="$4" want="$5"
    if [ -z "$b" ] || [ -z "$e" ]; then
        echo "FAIL: case $c: no $a phrase in the dump. A missing reading is a FAIL, never a pass."
        fail=1
        return
    fi
    if [ "$want" = moves ] && [ "$e" -le "$b" ]; then
        echo "FAIL: case $c: $a did not move toward evil/chaos (signed rank $b -> $e)."
        fail=1
    elif [ "$want" = still ] && [ "$e" -ne "$b" ]; then
        echo "FAIL: case $c: $a moved (signed rank $b -> $e) but should not have."
        fail=1
    else
        echo "  ok: case $c: $a signed rank $b -> $e ($want)"
    fi
}

# case <n> <name> <corpse> <load> <law/chaos-want> <good/evil-want>
run_one() {
    local n="$1" name="$2" corpse="$3" load="$4" lcw="$5" gew="$6"
    local ge_b ge_e lc_b lc_e
    run_case "$name" "$corpse" "$load"
    ge_b="$(axis "$RUN/logs/$name-pre.txt" good-evil)"
    ge_e="$(axis "$RUN/logs/$name-post.txt" good-evil)"
    lc_b="$(axis "$RUN/logs/$name-pre.txt" law-chaos)"
    lc_e="$(axis "$RUN/logs/$name-post.txt" law-chaos)"
    # Control: the eater starts decisively Good and decisively Lawful, so both
    # halves of the charge are able to land.
    if [ "${ge_b:-0}" -gt -8 ] || [ "${lc_b:-0}" -gt -8 ]; then
        echo "INCONCLUSIVE: case $n: the eater did not start decisively Good and"
        echo "              Lawful (good/evil ${ge_b:-?}, law/chaos ${lc_b:-?}). Run dir: $RUN"
        exit 2
    fi
    echo "case $n ($name): run dir $RUN"
    verdict "$n" law/chaos "$lc_b" "$lc_e" "$lcw"
    verdict "$n" good/evil "$ge_b" "$ge_e" "$gew"
}

run_one 1 human-own   human     "$HUMAN" moves moves
run_one 2 human-other dwarf     "$HUMAN" moves still
run_one 3 orc-own     "cave orc" ""      still moves
run_one 4 orc-other   human     ""       still still

if [ "$fail" -eq 0 ]; then
    echo "PASS: each eater was charged on exactly the axes the rule names."
fi
exit "$fail"
