#!/bin/bash
# gate: live
# Does wielding a wrong-alignment weapon drain two levels, and keep them? (bd inc-qaav4)
#
# THE RULING. Each wield of a holy, unholy, lawful, chaotic or balance weapon by
# a wrong-alignment wielder applies two negative levels through
# Character::DrainXP (src/Create.cpp:3226). Negative levels feed BONUS_NEGLEV on
# A_AID, which lowers every saving throw by 1 per level. The levels stay after
# the weapon is unwielded, and a second wield adds two more. Today a wield only
# changes that weapon's to-hit, damage and speed (src/Values.cpp:643-672), so
# this check is RED on a tree without the fix.
#
# fact: character, alignment and level -- fixture alignment-drain-warrior (INCURSION_LOAD): level 5 Chaotic Good orc warrior, 10000 XP
# fact: settings -- options-2026-08-22.dat (CHECK_OPTIONS)
# fact: monsters -- wizard "Genocide Everything" in the key script
# fact: the weapon and its wrong alignment -- wizard "Item Acquisition", Nine Lives Stealer +2: a fixed unholy long sword, wrong for Chaotic Good
# fact: wield, unwield, rewield -- scripted inventory keys, guarded by @expect on the slot text
# fact: the weapon's own penalty -- the Damage and Speed lines of the same sheets
# fact: the values read -- the character sheet (key script dumps sheet-0..3); no dice, no seed
#
# THE ORACLE, read from the four sheet dumps of tools/keys/alignment-drain-wield.keys:
#   Fortitude / Reflex / Will   the first signed number on each line
#   effective XP                the "XP" line (total XP minus drained XP, src/Sheet.cpp:58)
#   drained XP                  the "Drain" line, shown only when non-zero (src/Sheet.cpp:59)
#
# THE WEAPON'S OWN PENALTY must survive the fix (src/Values.cpp, via Creature::opposesAlignmentOf):
# -2 damage on the "Damage" line, -4 speed shown as "x 80%" on the "Speed" line, while it is wielded.
# Damage is the clean reading: negative levels do not touch it, so it isolates the weapon's -2.
#   sheet-1 and sheet-3 (wielded): Damage line carries "-2 neglev", Speed line ends "x 80%"
#   sheet-0 and sheet-2 (not the unholy sword): the Damage line carries no "neglev"
#
# FIVE PROPERTIES:
#   sheet-0  baseline: drained XP is 0
#   sheet-1  after the first wield:   each save == baseline - 2; drained XP > 0; effective XP lower
#   sheet-2  after the unwield:       each save == baseline - 2; drained XP unchanged
#   sheet-3  after the second wield:  each save == baseline - 4; drained XP greater than at sheet-1
#
# The check exits 2 when a sheet or a value is missing. It never reads absence as zero
# except for the "Drain" line, and only after the XP line of the same sheet was read.
#
# Usage: tools/check_alignment_drain.sh [--prove-red]   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/alignment-drain-warrior.sav
KEYS=tools/keys/alignment-drain-wield.keys
SEED=1

# The mutation: remove the level drain from the wield hook (Character::Wield, src/Inv.cpp). Every
# save, XP and drain assertion below then goes red. Declared, not yet run through --prove-red.
check_mutation src/Inv.cpp 'DrainLevels(2);' ''

[ -f "$FIXTURE" ] || _check_die 2 "the fixture is missing: $FIXTURE"
export INCURSION_LOAD="$FIXTURE"
check_run "$KEYS" "$SEED"
unset INCURSION_LOAD

check_screens '*sheet-[0-3]-*'
check_expect "Align  Chaotic Good" "the loaded character is the Chaotic Good fixture"

SC="$CHECK_RUN/logs/screens"

sheet() { # <n> -> the one dump file for sheet-<n>
    local f
    f="$(ls "$SC"/*-sheet-"$1"-*.txt 2>/dev/null | head -1)"
    [ -n "$f" ] || _check_die 2 "no dump for sheet-$1 in $SC; the key script stopped early."
    echo "$f"
}

# num <file> <label regexp> -> the first signed integer after the label, or exit 2
num() {
    local v
    v="$(sed -nE "s/^ *$2 +([+-]?[0-9]+).*/\1/p" "$1" | head -1)"
    [ -n "$v" ] || _check_die 2 "could not read '$2' from $1"
    echo "$v"
}

# Per sheet: FORT[n] REF[n] WILL[n] EXP[n] DRAIN[n]
for n in 0 1 2 3; do
    f="$(sheet $n)"
    FORT[$n]="$(num "$f" Fortitude)"
    REF[$n]="$(num "$f" Reflex)"
    WILL[$n]="$(num "$f" Will)"
    EXP[$n]="$(num "$f" XP)"
    DRAIN[$n]="$(sed -nE 's/^ *Drain +([0-9]+).*/\1/p' "$f" | head -1)"
    DRAIN[$n]="${DRAIN[$n]:-0}"
    echo "  sheet-$n: Fort ${FORT[$n]} Ref ${REF[$n]} Will ${WILL[$n]}  XP ${EXP[$n]}  Drain ${DRAIN[$n]}"
done

[ "${EXP[0]}" -gt 0 ] || _check_die 2 "baseline effective XP is ${EXP[0]}; the fixture should hold 10000."

bad() { echo "FAIL: $*"; CHECK_FAIL=1; }

[ "${DRAIN[0]}" -eq 0 ] || bad "the baseline already shows drained XP (${DRAIN[0]})."

saves_are() { # <sheet> <levels lost>
    local n="$1" d="$2"
    [ "${FORT[$n]}" -eq $((FORT[0] - d)) ] || bad "sheet-$n Fortitude is ${FORT[$n]}, wanted ${FORT[0]}-$d = $((FORT[0] - d))."
    [ "${REF[$n]}"  -eq $((REF[0]  - d)) ] || bad "sheet-$n Reflex is ${REF[$n]}, wanted ${REF[0]}-$d = $((REF[0] - d))."
    [ "${WILL[$n]}" -eq $((WILL[0] - d)) ] || bad "sheet-$n Will is ${WILL[$n]}, wanted ${WILL[0]}-$d = $((WILL[0] - d))."
}

saves_are 1 2
[ "${DRAIN[1]}" -gt 0 ]            || bad "sheet-1 shows no drained XP after the first wield."
[ "${EXP[1]}" -lt "${EXP[0]}" ]    || bad "sheet-1 effective XP did not fall (${EXP[0]} -> ${EXP[1]})."

saves_are 2 2
[ "${DRAIN[2]}" -eq "${DRAIN[1]}" ] || bad "sheet-2 drained XP changed on unwield (${DRAIN[1]} -> ${DRAIN[2]}); the levels must stay."

saves_are 3 4
[ "${DRAIN[3]}" -gt "${DRAIN[1]}" ] || bad "sheet-3 drained XP did not grow on the second wield (${DRAIN[1]} -> ${DRAIN[3]})."

line_of() { # <sheet n> <label> -> the sheet line that holds the label
    local l
    l="$(grep -E "^ *$2 " "$(sheet "$1")" | head -1)"
    [ -n "$l" ] || _check_die 2 "sheet-$1 has no '$2' line."
    echo "$l"
}
for n in 1 3; do
    case "$(line_of $n Damage)" in *"-2 neglev"*) ;; *) bad "sheet-$n Damage line lacks the weapon's own '-2 neglev': $(line_of $n Damage)" ;; esac
    case "$(line_of $n Speed)" in *"x 80%"*) ;; *) bad "sheet-$n Speed line lacks the weapon's own 'x 80%': $(line_of $n Speed)" ;; esac
done
for n in 0 2; do
    case "$(line_of $n Damage)" in *neglev*) bad "sheet-$n Damage line shows a weapon penalty it should not: $(line_of $n Damage)" ;; esac
done

check_done "each wield of the unholy sword took two levels from a Chaotic Good warrior, and unwielding gave none back"
