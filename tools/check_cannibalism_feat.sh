#!/bin/bash
# gate: live
# Does the Cannibalism feat work, and is it closed to a good character? (bd inc-08js)
#
# THE RULE UNDER TEST (src/FeatTab.cpp, src/Create.cpp, src/Creature.cpp):
#   - Character::FeatPrereq refuses FT_CANNIBALISM to a good character, so the
#     feat menu does not list it for one.
#   - Creature::HasAbility(CA_DEVOURING) is true for a feat holder, so
#     Creature::DevourMonster (src/Skills.cpp) does not return early and pays
#     experience for the corpse.
#
# THREE SESSIONS, seed 4, one headless run each:
#   feat     tools/keys/cannibalism-feat-yes.keys  neutral human warrior, takes
#            Cannibalism at creation, eats a brown bear corpse.
#   control  tools/keys/cannibalism-feat-no.keys   the same warrior, no feat
#            (every feat is the first one offered), eats the same corpse.
#   good     tools/keys/cannibalism-feat-good.keys a human paladin (Lawful Good,
#            forced by the class) opens the first feat menu.
#
# HOW THE FEAT IS GRANTED. A human gets bonus feats at first level. The feat
# menu ("Choose a feat; the following are available:") lists Cannibalism for a
# character who is not good, and @choose "Cannibalism" takes it by name. No
# wizard command is used.
#
# THE ORACLES.
#   1/2  The "XP" line of the game's own character dump (the sheet's [W]rite
#        Dump), before and after the meal in one session. The meal is a brown
#        bear corpse (CR 5, not sapient, so no alignment charge): DevourMonster
#        pays CR*50 = 250 XP when the corpse outranks the eater. The feat case
#        MUST rise from 0 to a positive number, and the control MUST stay at 0.
#        Genocide Everything (the kill) pays no XP, so the control proves the
#        rise is the devouring.
#   3    The menu screen photographed at the first feat choice. The neutral
#        warrior's menu MUST list Cannibalism; the paladin's MUST NOT, and its
#        menu MUST hold exactly one entry less than the neutral warrior's
#        ("of 56" against "of 55"; both draw the same seed-4 attribute rolls).
#
# A RUN THAT MEASURED NOTHING is INCONCLUSIVE (exit 2), not a pass: a meal case
# needs the message "You finish eating the brown bear corpse" and both dumps; a
# menu case needs a feat menu on screen.
#
# Usage: tools/check_cannibalism_feat.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=4
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"
STAMP="$$"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# run_keys <keyscript> <tag>  -> sets RUN
run_keys() {
    local out
    out="$(INCURSION_RUN_DIR="logs/runs/cannibalism-feat-$2-$STAMP" \
           INCURSION_OPTIONS="$OPTIONS" \
           tools/headless.sh "tools/keys/cannibalism-feat-$1.keys" "$SEED" 2>&1 </dev/null)"
    RUN="$(echo "$out" | awk '/^run:/ {print $2}')"
    if [ -z "$RUN" ] || grep -qE 'the key script looked for something' <<<"$out"; then
        echo "INCONCLUSIVE: session $1 did not complete."
        echo "$out" | tail -12
        exit 2
    fi
}

# meal <name> -> sets RUN, MPRE, MPOST (not a subshell: exit must stop the check)
meal() {
    local pre post
    run_keys "$1" "$1"
    pre="$(awk '/^XP / {print $2; exit}' "$RUN/logs/meal-pre.txt" 2>/dev/null)"
    post="$(awk '/^XP / {print $2; exit}' "$RUN/logs/meal-post.txt" 2>/dev/null)"
    if [ -z "$pre" ] || [ -z "$post" ]; then
        echo "INCONCLUSIVE: session $1 wrote no XP line in a dump. Run dir: $RUN"
        exit 2
    fi
    if ! grep -qF "You finish eating the brown bear corpse" "$RUN"/logs/screens/*-log-meal.txt 2>/dev/null; then
        echo "INCONCLUSIVE: session $1: the message log never says the corpse was eaten. Run dir: $RUN"
        exit 2
    fi
    MPRE="$pre"; MPOST="$post"
}

fail=0

meal yes; fpre="$MPRE"; fpost="$MPOST"
echo "feat    ($RUN): XP $fpre -> $fpost"
if [ "$fpost" -gt "$fpre" ]; then
    echo "  ok: the feat holder gained experience from the corpse"
else
    echo "FAIL: the feat holder gained no experience (XP $fpre -> $fpost)."
    fail=1
fi
YESRUN="$RUN"

meal no; cpre="$MPRE"; cpost="$MPOST"
echo "control ($RUN): XP $cpre -> $cpost"
if [ "$cpost" -eq "$cpre" ]; then
    echo "  ok: without the feat the same meal paid nothing"
else
    echo "FAIL: the control gained experience (XP $cpre -> $cpost) with no feat."
    fail=1
fi

# Feat menu: neutral warrior (inside the feat session) and good paladin.
menu() {   # menu <screen file> -> sets ML, MT ; exits 2 if not a feat menu
    local f="$1" listed=0 total
    grep -q "Choose a feat; the following are available" "$f" || {
        echo "INCONCLUSIVE: $f is not a feat menu."; exit 2; }
    grep -q "Cannibalism" "$f" && listed=1
    total="$(grep -oE '1-[0-9]+ of [0-9]+' "$f" | head -1 | awk '{print $3}')"
    [ -n "$total" ] || { echo "INCONCLUSIVE: $f shows no menu total."; exit 2; }
    ML="$listed"; MT="$total"
}

NEUTRAL="$(ls "$YESRUN"/logs/screens/*-featlist.txt 2>/dev/null | head -1)"
[ -n "$NEUTRAL" ] || { echo "INCONCLUSIVE: no feat menu dump in $YESRUN"; exit 2; }
menu "$NEUTRAL"; nl="$ML"; nt="$MT"

run_keys good good
GOOD="$(ls "$RUN"/logs/screens/*-featlist.txt 2>/dev/null | head -1)"
[ -n "$GOOD" ] || { echo "INCONCLUSIVE: no feat menu dump in $RUN"; exit 2; }
menu "$GOOD"; gl="$ML"; gt="$MT"
echo "menu: neutral lists Cannibalism=$nl (of $nt entries); good lists it=$gl (of $gt entries)"

if [ "$nl" -eq 1 ]; then
    echo "  ok: a non-good character is offered Cannibalism"
else
    echo "FAIL: a non-good character is not offered Cannibalism."
    fail=1
fi
if [ "$gl" -eq 0 ] && [ "$gt" -eq $((nt - 1)) ]; then
    echo "  ok: a good character is not offered it (menu one entry shorter)"
else
    echo "FAIL: good menu lists it=$gl, entries $gt against neutral $nt."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: the feat devours for a non-good holder and is closed to a good character."
fi
exit "$fail"
