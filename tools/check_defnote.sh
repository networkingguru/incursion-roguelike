#!/bin/bash
# gate: live
# Do the sidebar and the character sheet show the defense a resource adds inside
# each strike? (bd inc-7v2i)
#
# THE DEFECT. Shield, Nemesis Spell, Combat Mind, Dispel Evil, the blinding
# armor quality and water add defense in an EV_STRIKE script (e.vDef += ...), not
# to the stored defense. The sidebar Def: and the sheet's Defense Class read only
# the stored value, so a player with Shield up saw Def:12 while attackers rolled
# against 17.
#
# REQUIRED. Each resource declares its own sheet line with MSG_DEFNOTE
# (inc/Defines.h). Sidebar: Def:N+F, F the sum of the constant bonuses, a '*'
# when one varies by attacker. Sheet: one line per active source, under the
# Defense Class line.
#
# THE ORACLES. (a) the sidebar on the screen dump after the cast; (b) the sheet
# screen; (c) the engine's own attack line "vs. Def N +5 shield = M", which the
# sum in the sidebar must match. Fixture: orc-mage-seed4-gate (Henk, a Mage 1
# who knows Shield, Def 12).
#
# fact: the fixture's stored Def, 12 -- read off the arrival screen, never hard-coded
# fact: Shield's cost and success -- frozen .sav (INCURSION_LOAD), 67 of 72 mana left after the cast
# fact: the Shield bonus, 5 -- lib/wspells.irh Shield, read back through the screens
# fact: a goblin gets an attack in four steps -- not controlled; without one the (c) assertion is INCONCLUSIVE (exit 2)
# fact: the attack's roll and hit or miss -- not read; only the printed Def sum
# fact: dungeon, other monsters -- the fixture's frozen map; only the screens are read
# fact: the blinding armor, padded armour +8 coverage -- wizard menu "Item Acquisition" and "Add Quality to Armour" (src/Debug.cpp cases 4 and 13), no dice; the bonus 2 is lib/m_items.irh
# fact: the water square -- wizard menu "Change terrain type" puts shallow water on the square east of the player; the bonus 8 is lib/dungeon.irh WATER_COMBAT
# fact: the aerial case -- Levitation, learned through the wizard menu and cast, no save to resist
# fact: Nemesis Spell, Dispel Evil, Combat Mind known -- "Learn Any Spell" (src/Debug.cpp case 17), cast from the Spell Manager with the fixture's 72 mana
# fact: Nemesis Spell's number -- read off the sheet and compared with the "NS" term the goblin's attack line prints; never hard-coded
# fact: Nemesis Spell's target -- the spell has no qval, so it names the caster as its nemesis; the check reads only the -N term against the goblin
# fact: Combat Mind is usable -- a goblin is summoned and the player swings first, because the power refuses while flat-footed (lib/alchemy.irh PRE(EV_EFFECT))
# fact: the sidebar wrap -- Shield 5 + Blinding 2 + Water 8 = 15 constant, Dispel Evil adds the '*'; 12 turns between the two casts let the casting timeout end
# fact: the sidebar width -- 15 columns, read through the wrapped screen, not assumed
#
# Usage: tools/check_defnote.sh [--prove-red [shield|blinding|water|nemesis|dispelevil|combatmind]]
#   0 pass   1 fail   2 could not measure
# --prove-red breaks ONE source (Shield unless named): it removes that
# resource's MSG_DEFNOTE line. The source name is passed on to the inner re-run.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/orc-mage-seed4-gate.sav
SEED=4
[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE."

# Break it: a resource stops declaring its note. Its sidebar suffix and sheet
# line must go quiet. --prove-red performs ONE mutation, the source named on the
# command line (Shield by default); an ordinary run guards every site.
SRC="${CHECK_ARGS[0]:-shield}"
declare_mutation() { # <source>
    case "$1" in
    shield)     check_mutation lib/wspells.irh \
        'On Event MSG_DEFNOTE "Shield: +5 vs. physical attacks, unless you are flanked, surprised or flat-footed." / "5";
' '' ;;
    blinding)   check_mutation lib/m_items.irh \
        'On Event MSG_DEFNOTE "Blinding: +2 vs. attackers who can see you." / "2";' '' ;;
    water)      check_mutation lib/dungeon.irh \
        'On Event MSG_DEFNOTE "Water: +8 vs. attackers outside the water, unless you are flying." / "8";' '' ;;
    nemesis)    check_mutation lib/wspells.irh \
        'MSG_DEFNOTE "Nemesis Spell: +<N> vs. your nemesis, unless it is shielded from divination; -<N> vs. all other attackers." / "*",' '' ;;
    dispelevil) check_mutation lib/pspells.irh \
        'On Event MSG_DEFNOTE "Dispel Evil: +4 vs. evil attackers, +6 vs. creatures evil by nature. This bonus does not stack with a deflection bonus." / "*";' '' ;;
    combatmind) check_mutation lib/alchemy.irh \
        'On Event MSG_DEFNOTE "Combat Mind: your Intelligence minus the attacker'"'"'s, doubled vs. humanoids, vs. sapient attackers only." / "*";' '' ;;
    *) _check_die 2 "unknown source '$1'. Choose shield, blinding, water, nemesis, dispelevil or combatmind." ;;
    esac
}
if [ "$CHECK_PROVE_RED" = 1 ] || [ "${CHECK_MUTATED:-0}" = 1 ]; then
    declare_mutation "$SRC"
else
    for _s in shield blinding water nemesis dispelevil combatmind; do declare_mutation "$_s"; done
fi

# read_def: the stored Def off the arrival screen of the run just made.
read_def() {
    check_screens '*-arrival'
    DEF="$(grep -ohE 'Def:[0-9]+' "$CHECK_RUN"/logs/screens/*-arrival.txt | head -1 | sed 's/Def://')"
    [ -n "$DEF" ] || _check_die 2 "cannot read the stored Def off the arrival screen."
}

export INCURSION_LOAD="$FIXTURE"

check_run tools/keys/defnote-shield.keys "$SEED"

check_screens '*-arrival'
check_expect "Def:" "precondition: the sidebar shows Def before the cast" ||
    _check_die 2 "precondition failed: no Def: on the arrival screen."
DEF="$(grep -ohE 'Def:[0-9]+' "$CHECK_RUN"/logs/screens/*-arrival.txt | head -1 | sed 's/Def://')"
[ -n "$DEF" ] || _check_die 2 "cannot read the stored Def off the arrival screen."
echo "  stored Def before the cast: $DEF"
check_reject "Def:$DEF+" "before the cast there is no bonus suffix"

check_screens '*-after'
check_expect "Def:$DEF+5" "AC1: the sidebar shows Def:$DEF+5 with Shield up"

check_screens '*-sheet'
check_expect "Shield: +5 vs. physical attacks, unless you are flanked," "AC1/AC2: the sheet states the +5 and its condition"
check_expect "surprised or flat-footed." "AC2: the sheet line carries the whole condition"

# (c) the sidebar sum against the engine's own attack line.
check_run tools/keys/defnote-shield-hit.keys "$SEED"
check_screens '*-step*'
if grep -qF -- "vs. Def $DEF +5 shield = $((DEF + 5))" "${CHECK_SCREENS[@]}"; then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    AC5: the attack line reads 'vs. Def $DEF +5 shield = $((DEF + 5))', matching Def:$DEF+5"
elif grep -qE -- "vs\. Def [0-9]+" "${CHECK_SCREENS[@]}"; then
    echo "  FAIL  AC5: the attack line has a Def sum other than $DEF +5 shield = $((DEF + 5)):"
    grep -hoE -- "vs\. Def [^[]*" "${CHECK_SCREENS[@]}" | head -2 | sed 's/^/        /'
    CHECK_FAIL=1
else
    _check_die 2 "no goblin attack line reached the screen in four steps."
fi

# --- the five other sources ------------------------------------------------

# Blinding: armor with the quality.
check_run tools/keys/defnote-blinding.keys "$SEED"
read_def
check_reject "Def:$DEF+" "blinding: before the quality there is no bonus suffix"
check_screens '*-after'
check_expect "Def:$DEF+2 Cov:" "blinding: the sidebar shows Def:$DEF+2 beside the coverage"
check_screens '*-sheet'
check_expect "Blinding: +2 vs. attackers who can see you." "blinding: the sheet states the +2 and its condition"

# Water: one square of shallow water, stepped into; then the same while levitating.
check_run tools/keys/defnote-water.keys "$SEED"
read_def
check_reject "Def:$DEF+" "water: before the step there is no bonus suffix"
check_screens '*-in'
check_expect "Def:$DEF+8" "water: the sidebar shows Def:$DEF+8 in the water"
check_screens '*-sheet'
check_expect "Water: +8 vs. attackers outside the water," "water: the sheet states the +8 and its condition"
check_run tools/keys/defnote-water-aerial.keys "$SEED"
read_def
check_screens '*-in'
check_expect "Levitating" "water, aerial: the precondition holds, the player is levitating"
check_reject "Def:$DEF+" "water, aerial: no bonus suffix while levitating over the water"
check_screens '*-sheet'
check_reject "Water:" "water, aerial: the sheet has no Water line while levitating"

# Nemesis Spell: '*' on the sidebar, a live number on the sheet that equals the
# engine's own NS term in the goblin's attack line.
check_run tools/keys/defnote-nemesis.keys "$SEED"
read_def
check_reject "Def:$DEF*" "nemesis: before the cast there is no '*'"
check_screens '*-after'
check_expect "Def:$DEF*" "nemesis: the sidebar shows Def:$DEF*"
check_screens '*-sheet'
check_expect "Nemesis Spell: +" "nemesis: the sheet has the Nemesis Spell line"
NS="$(grep -ohE 'Nemesis Spell: \+[0-9]+' "$CHECK_RUN"/logs/screens/*-sheet.txt | head -1 | sed 's/.*+//')"
check_screens '*-step*'
if [ -z "$NS" ]; then
    echo "  FAIL  nemesis: no number on the sheet line"
    CHECK_FAIL=1
elif grep -qE -- "vs\. Def $DEF -?[0-9]* ?(noDex)? ?-$NS NS" "${CHECK_SCREENS[@]}"; then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    nemesis: the sheet says $NS and the goblin's attack line carries -$NS NS"
elif grep -q -- " NS = " "${CHECK_SCREENS[@]}"; then
    echo "  FAIL  nemesis: the sheet says $NS but the attack line differs:"
    grep -hoE -- "vs\. Def [^[]*" "${CHECK_SCREENS[@]}" | head -2 | sed 's/^/        /'
    CHECK_FAIL=1
else
    _check_die 2 "no goblin attack line with an NS term reached the screen in four steps."
fi

# Dispel Evil: a priest spell, learned and cast by the mage.
check_run tools/keys/defnote-dispelevil.keys "$SEED"
read_def
check_screens '*-after'
check_expect "Def:$DEF*" "dispel evil: the sidebar shows Def:$DEF*"
check_screens '*-sheet'
check_expect "Dispel Evil: +4 vs. evil attackers," "dispel evil: the sheet states the +4 and the +6"

# Combat Mind: a psionic power, learned through the wizard menu.
check_run tools/keys/defnote-combatmind.keys "$SEED"
read_def
check_screens '*-after'
check_expect "Def:$DEF*" "combat mind: the sidebar shows Def:$DEF*"
check_expect "Combat Mind |" "combat mind: the power is up (status bar)"
check_screens '*-sheet'
check_expect "Combat Mind: your Intelligence minus the attacker's," "combat mind: the sheet has the Combat Mind line"

# The sidebar wrap: Shield + Blinding + Water + Dispel Evil, Cov:8.
check_run tools/keys/defnote-wrap.keys "$SEED"
read_def
check_screens '*-wrapped'
if grep -A1 -E -- "\|Def:$DEF\+15\*$" "${CHECK_SCREENS[@]}" | grep -qE -- "\|    Cov:8$"; then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    wrap: 'Def:$DEF+15*' then 'Cov:8' on a second line"
else
    echo "  FAIL  wrap: the sidebar does not show Def:$DEF+15* over an indented Cov:8"
    grep -h -A1 -E -- "\|Def:" "${CHECK_SCREENS[@]}" | sed 's/^/        /'
    CHECK_FAIL=1
fi
check_screens '*-sheet'
check_expect "Water: +8" "wrap: the sheet lists all four sources (water)"
check_expect "Blinding: +2" "wrap: ... blinding"
check_expect "Shield: +5" "wrap: ... shield"
check_expect "Dispel Evil: +4" "wrap: ... dispel evil"

check_done "every defense note shows on the sidebar and the sheet; Shield matches the attack line"
