#!/bin/bash
# gate: live
# Do the Orc, Black Orc and Dragonkin races still devour, now that they get it
# from the Cannibalism feat instead of Ability[CA_DEVOURING]? (bd inc-6at2)
#
# THE RULE UNDER TEST (lib/races.irh Orc, lib/subraces.irh Dragonkin and Black
# Orc): each race grants Feat[FT_CANNIBALISM] at 1st level. The feat makes
# Creature::HasAbility(CA_DEVOURING) true (src/Creature.cpp), so the race
# devours. The feat's own prerequisite (Character::FeatPrereq) refuses it to a
# good character, but a race grant MUST give it regardless.
#
# FIVE SESSIONS, seed 4 for new characters, seed 1 for loaded ones:
#   1 new orc        Lawful Good orc paladin (tools/keys/racial-cannibalism-orc.keys)
#                    eats a brown bear corpse. Feat list AND XP rise.
#   2 new dragonkin  dragonkin barbarian (racial-cannibalism-dragonkin.keys),
#                    same meal. Feat list AND XP rise.
#   3 new black orc  Black Orc barbarian (racial-cannibalism-blackorc.keys),
#                    feat list only.
#   4 old orc        tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav, made
#                    BEFORE the change, loaded, eats the same corpse.
#   5 old dragonkin  tools/fixtures/chars/dragonkin-sheet-seed1-opt0818.sav,
#                    likewise.
#   (cases 4 and 5 use tools/keys/cannibalism-feat-meal.keys unchanged.)
#
# THE ORACLES, both the game's own character dump ([W]rite Dump):
#   feat list  a "Feats:" block that holds a "Cannibalism" line.
#   XP         the "XP" line before and after the meal in ONE session. The meal
#              is a brown bear corpse (CR 5, not sapient, no alignment charge);
#              Creature::DevourMonster pays 250 XP. Without devouring it pays 0.
#
# A fixture that already lists Cannibalism on its saved sheet is no longer a
# pre-change character: INCONCLUSIVE. A run that measured nothing is
# INCONCLUSIVE (exit 2), not a pass: a meal case needs the message "You finish
# eating the brown bear corpse" and both dumps; a feat case needs the dump.
#
# Usage: tools/check_racial_cannibalism.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OPT22=tools/fixtures/options-2026-08-22.dat
OPT18=tools/fixtures/options-2026-08-18.dat
STAMP="$$"
ORCSAV=tools/fixtures/chars/orc-barbarian-seed1-opt0822
DRGSAV=tools/fixtures/chars/dragonkin-sheet-seed1-opt0818

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
for f in $OPT22 $OPT18 "$ORCSAV.sav" "$ORCSAV.sheet.txt" "$DRGSAV.sav" "$DRGSAV.sheet.txt"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: missing $f"; exit 2; }
done
for s in "$ORCSAV.sheet.txt" "$DRGSAV.sheet.txt"; do
    if grep -q "Cannibalism" "$s"; then
        echo "INCONCLUSIVE: $s already lists Cannibalism, so it is not a pre-change character."
        exit 2
    fi
done

# run_case <tag> <keyscript> <seed> <options> [save]  -> sets RUN
run_case() {
    local tag="$1" keys="$2" seed="$3" opt="$4" load="${5:-}" out
    out="$(INCURSION_RUN_DIR="logs/runs/racial-cannibalism-$tag-$STAMP" \
           INCURSION_OPTIONS="$opt" INCURSION_LOAD="$load" \
           tools/headless.sh "$keys" "$seed" 2>&1 </dev/null)"
    RUN="$(awk '/^run:/ {print $2}' <<<"$out")"
    if [ -z "$RUN" ] || grep -qE 'NO GAMEPLAY|the key script looked for something' <<<"$out"; then
        echo "INCONCLUSIVE: case $tag did not complete."
        tail -12 <<<"$out"
        exit 2
    fi
}

# xp_of <dump> -> XP value, empty when absent
xp_of() { awk '/^XP / {print $2; exit}' "$1" 2>/dev/null; }

# has_feat <dump>: true when the dump's Feats block lists Cannibalism.
# Exits 2 when the dump has no Feats block at all.
has_feat() {
    [ -s "$1" ] && grep -q '^Feats:' "$1" || {
        echo "INCONCLUSIVE: $1 holds no Feats block."; exit 2; }
    awk '/^Feats:/ {on=1; next} on && /^$/ {exit} on && /^  Cannibalism$/ {f=1} END {exit !f}' "$1"
}

fail=0
# meal_case <tag> <label> <keys> <seed> <options> <expect-feat: yes|no> [save]
meal_case() {
    local tag="$1" label="$2" keys="$3" seed="$4" opt="$5" wantfeat="$6" load="${7:-}"
    local pre post feat
    run_case "$tag" "$keys" "$seed" "$opt" "$load"
    pre="$(xp_of "$RUN/logs/meal-pre.txt")"; post="$(xp_of "$RUN/logs/meal-post.txt")"
    if [ -z "$pre" ] || [ -z "$post" ]; then
        echo "INCONCLUSIVE: case $tag wrote no XP line in a dump. Run dir: $RUN"; exit 2
    fi
    if ! grep -qF "You finish eating the brown bear corpse" "$RUN"/logs/screens/*-log-meal.txt 2>/dev/null; then
        echo "INCONCLUSIVE: case $tag: the message log never says the corpse was eaten. Run dir: $RUN"; exit 2
    fi
    if [ "$wantfeat" = yes ]; then
        if has_feat "$RUN/logs/meal-pre.txt"; then feat=listed; else feat=absent; fi
    else
        feat=n/a
    fi
    echo "$label ($RUN): XP $pre -> $post, Cannibalism $feat"
    if [ "$post" -gt "$pre" ]; then
        echo "  ok: the meal paid experience"
    else
        echo "FAIL: $label gained no experience (XP $pre -> $post)."; fail=1
    fi
    if [ "$wantfeat" = yes ] && [ "$feat" != listed ]; then
        echo "FAIL: $label does not list Cannibalism among its feats."; fail=1
    fi
}

# Alignment control for case 1: the dump must say the orc is Good.
meal_case orc "new orc (Lawful Good)" tools/keys/racial-cannibalism-orc.keys 4 "$OPT22" yes
if grep -q '^Align  Lawful Good' "$RUN/logs/meal-pre.txt"; then
    echo "  ok: the orc is Lawful Good, so the feat's prerequisite did not apply"
else
    echo "INCONCLUSIVE: the new orc is not Lawful Good. Run dir: $RUN"; exit 2
fi

meal_case dragonkin "new dragonkin" tools/keys/racial-cannibalism-dragonkin.keys 4 "$OPT22" yes

run_case blackorc tools/keys/racial-cannibalism-blackorc.keys 4 "$OPT22"
if has_feat "$RUN/logs/blackorc-sheet.txt"; then
    echo "new black orc ($RUN): Cannibalism listed"
    echo "  ok: the Black Orc has the feat"
else
    echo "new black orc ($RUN): Cannibalism absent"
    echo "FAIL: a new Black Orc does not list Cannibalism among its feats."; fail=1
fi
grep -q '^Race   Black Orc' "$RUN/logs/blackorc-sheet.txt" || {
    echo "INCONCLUSIVE: the black orc case did not make a Black Orc. Run dir: $RUN"; exit 2; }

meal_case oldorc "old orc save" tools/keys/cannibalism-feat-meal.keys 1 "$OPT22" no "$ORCSAV.sav"
meal_case olddragonkin "old dragonkin save" tools/keys/cannibalism-feat-meal.keys 1 "$OPT18" no "$DRGSAV.sav"

if [ "$fail" -eq 0 ]; then
    echo "PASS: new and old orc, black orc and dragonkin characters all devour through the feat."
fi
exit "$fail"
