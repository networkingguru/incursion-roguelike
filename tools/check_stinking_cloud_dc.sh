#!/bin/bash
# gate: live
# inc-s64e: does a stinking cloud roll the Fortitude DC the game says it does?
# Needs the posix build: BACKEND=posix ./build_macos.sh
#
# THE DEFECT. The cast spell's per-round strike rolled a fixed DC 20, and the
# terrain form rolled DC 20 too, while the spell's own text promised the
# caster's DC and the terrain's move warning came from the same constant.
#   CAST     each round's save must use the caster's spell DC (Field::FieldDC
#            -> Creature::getSpellDC, src/Status.cpp), not 20.
#   TERRAIN  the "stinking cloud;terrain" EV_MOVE save must use WARN_SAVE_DC,
#            15 (lib/dungeon.irh), and the move warning must show that save's
#            chance.
#
# THE ORACLE is logs/chance_probe.log (INCURSION_CHANCE_PROBE, src/Skills.cpp):
# one line per Creature::SavingThrow, "save <type 0/1/2> <DC> <predicted%> <0/1>".
# Type 0 is Fortitude. The DC column is the DC actually rolled against.
#
# THE EXPECTED CAST DC does not call FieldDC again. It is computed here:
# 10 + the spell's level (read from lib/wspells.irh) + the best of the
# fixture's WIS and CHA modifiers (read from its sheet). Learn Any Spell gives
# the spell SP_PRIMAL|SP_INNATE (src/Debug.cpp:862), so getSpellDC takes the
# better of WIS and CHA. For the fixture that is 10 + 3 + 4 = 17.
# The TERRAIN DC is the rule itself: 15. The move warning must show the chance
# the probe predicted for those saves, so the number shown is the number rolled.
#
# Exit 0 pass, 1 fail ("measured nothing" counts as fail).
#
# fact: character (elf mage, WIS 16, CHA 18) -- fixture elf-mage-illusions-seed1, INCURSION_LOAD
# fact: wizard mode, Infinite Mana, Freeze Monsters on -- saved in the fixture; Cheat Death set by tools/keys/stinking-cloud-cast.keys
# fact: the map and its monsters -- the fixture's save pins the dungeon; the cast script clears the level with Genocide Everything
# fact: Stinking Cloud known -- wizard Learn Any Spell
# fact: three stinking cloud squares east of him -- wizard Change terrain type (tools/keys/stinking-cloud-terrain.keys)
# fact: each save's DC and predicted% -- read from chance_probe.log, the engine's own record
# fact: each save's die -- never read; the check asserts the DC column only
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo 'FAIL: measured nothing; build with BACKEND=posix ./build_macos.sh'; exit 1; }
OPTS=tools/fixtures/options-2026-08-22.dat
FIX=tools/fixtures/chars/elf-mage-illusions-seed1
SEED=1
status=0

# run_session <name> <keys> -> prints the run directory; fails when nothing ran
run_session() {
    local out run
    out="$(INCURSION_CHANCE_PROBE=1 INCURSION_LOAD="$FIX.sav" INCURSION_OPTIONS="$OPTS" \
           INCURSION_RUN_DIR="logs/stinking-cloud-dc.$$-$1" \
           tools/headless.sh "$2" "$SEED" 2>&1 < /dev/null)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if [ -z "$run" ] || grep -q 'NO GAMEPLAY\|gave up after\|looked for something' <<< "$out"; then
        echo "FAIL: $2 measured nothing (script did not complete)" >&2
        return 1
    fi
    echo "$run"
}

# modifier of one attribute from the fixture sheet: "WIS: 16/00 [+3/+2]" -> 3
sheet_mod() {
    sed -n "/^$1: /{s/^$1: *[0-9]*\/[0-9]* \[\([-+][0-9]*\)\/.*/\1/p;q;}" "$FIX.sheet.txt"
}

# ---- CAST --------------------------------------------------------------
lvl="$(awk '/^Wizard \/ Scroll Spell "Stinking Cloud"/ {f=1} f && /Level:/ {sub(/.*Level: */,""); sub(/;.*/,""); print; exit}' lib/wspells.irh)"
wis="$(sheet_mod WIS)"; cha="$(sheet_mod CHA)"
if [ -z "$lvl" ] || [ -z "$wis" ] || [ -z "$cha" ]; then
    echo "FAIL: measured nothing: spell level [$lvl], WIS mod [$wis], CHA mod [$cha] not read"
    exit 1
fi
best=$(( wis > cha ? wis : cha ))
want_cast=$(( 10 + lvl + best ))
run="$(run_session cast tools/keys/stinking-cloud-cast.keys)" || exit 1
log="$run/logs/chance_probe.log"
got="$([ -f "$log" ] && awk '$1=="save" {print $2 ":" $3}' "$log" | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
n="$([ -f "$log" ] && grep -c '^save ' "$log")"
only="$([ -f "$log" ] && awk '$1=="save" {print $2 ":" $3}' "$log" | sort -u | tr '\n' ' ')"
echo "CAST: expected Fortitude DC $want_cast (10 + level $lvl + best of WIS $wis, CHA $cha); rolled [$got] ($run)"
if [ "${n:-0}" -ge 5 ] && [ "$only" = "0:$want_cast " ]; then
    echo "CAST ok: $n per-round saves, all Fortitude DC $want_cast"
else
    echo "FAIL: CAST: need >= 5 saves, every one Fortitude DC $want_cast"
    status=1
fi

# ---- TERRAIN -----------------------------------------------------------
want_terr=15
run="$(run_session terrain tools/keys/stinking-cloud-terrain.keys)" || exit 1
log="$run/logs/chance_probe.log"
n="$([ -f "$log" ] && grep -c '^save ' "$log")"
only="$([ -f "$log" ] && awk '$1=="save" {print $2 ":" $3}' "$log" | sort -u | tr '\n' ' ')"
pred="$([ -f "$log" ] && awk '$1=="save" {print $4}' "$log" | sort -u | tr '\n' ' ' | sed 's/ *$//')"
shown="$(sed -n 's/.*(Fortitude \([0-9]*\)%).*/\1/p' "$run"/logs/screens/*-entry.txt | head -1)"
echo "TERRAIN: expected Fortitude DC $want_terr; rolled [$only] predicted [$pred] warning shows [${shown}%] ($run)"
if [ "${n:-0}" -ge 3 ] && [ "$only" = "0:$want_terr " ]; then
    echo "TERRAIN ok: $n saves, all Fortitude DC $want_terr"
else
    echo "FAIL: TERRAIN: need >= 3 saves, every one Fortitude DC $want_terr"
    status=1
fi
if [ -n "$shown" ] && [ "$pred" = "$shown" ]; then
    echo "TERRAIN ok: the move warning shows ${shown}%, the chance of the DC rolled"
else
    echo "FAIL: TERRAIN: the move warning shows [${shown}] but the saves predict [$pred]"
    status=1
fi

[ "$status" = 0 ] && echo "PASS: a stinking cloud rolls the DC it advertises, cast and terrain" || echo "FAIL"
exit "$status"
