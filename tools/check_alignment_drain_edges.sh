#!/bin/bash
# gate: live
# The edges of the alignment-weapon drain: level 2 lives, level 1 is asked to die, balance rule. (bd inc-qaav4)
#
# Companion to tools/check_alignment_drain.sh (the happy path: saves, XP, the weapon's own penalty).
# Four runs on frozen fixtures, each read from character-sheet and message-line dumps:
#
#   A. effective level 2, Chaotic Good, wields the unholy Nine Lives Stealer once.
#      He LIVES: no "Die?" prompt; effective XP 0; drained XP 1000; Fortitude, Reflex and Will each 1 lower.
#   B. effective level 1, Chaotic Good, wields it once. DrainLevels targets below level 1, so DrainXP
#      kills him: the wield prints "uneasy" and then "You die... Die? [yn]" (Explore Mode asks first).
#   C. BALANCE, Lawful Neutral wielder, weapon stamped WQ_BALANCE: no "uneasy", no death prompt, nothing drained.
#   D. CONTROL for C: the same Lawful Neutral fixture, weapon stamped WQ_CHAOTIC (wrong for a lawful
#      wielder): "uneasy" AND the death prompt (he is level 1), so the C run could have seen a drain.
#   E. BALANCE, Chaotic Good level 5, weapon stamped WQ_BALANCE: "uneasy" and saves exactly 2 lower, drain > 0.
#
# Without the fix: A and E show no drain (RED); B and D show no death prompt (RED); C is RED too when the
# old balance test (!isMType(MA_NEUTRAL)) still printed "uneasy" for a Lawful Neutral wielder.
#
# fact: characters -- fixtures alignment-drain-level1, -level2, -lawful-neutral, -warrior (INCURSION_LOAD)
# fact: settings -- options-2026-08-22.dat (CHECK_OPTIONS)
# fact: monsters -- wizard "Genocide Everything" (A, B) or none reachable in the few turns passing (C, D, E)
# fact: the unholy weapon -- wizard "Item Acquisition", Nine Lives Stealer +2, a fixed unholy long sword
# fact: a balance or chaotic weapon -- wizard "Add Quality to Weapon" on the starting weapon; the quality is typed, never rolled
# fact: the values read -- character sheets and the message line of dumped screens; no dice, no seed
#
# Usage: tools/check_alignment_drain_edges.sh   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FX=tools/fixtures/chars
SEED=1

# Declared so --prove-red can break the same site as tools/check_alignment_drain.sh. Not yet run.
check_mutation src/Inv.cpp 'DrainLevels(2);' ''

run() { # <fixture name> <key script>
    [ -f "$FX/$1.sav" ] || _check_die 2 "the fixture is missing: $FX/$1.sav"
    export INCURSION_LOAD="$FX/$1.sav"
    check_run "tools/keys/$2" "$SEED"
    unset INCURSION_LOAD
    S="$CHECK_RUN/logs/screens"
}

dump() { # <label glob> -> the one dump file
    local f
    f="$(ls "$S"/*-$1.txt 2>/dev/null | head -1)"
    [ -n "$f" ] || _check_die 2 "no dump '$1' in $S; the key script stopped early."
    echo "$f"
}

num() { # <file> <label> -> first signed integer after the label, or exit 2
    local v
    v="$(sed -nE "s/^ *$2 +([+-]?[0-9]+).*/\1/p" "$1" | head -1)"
    [ -n "$v" ] || _check_die 2 "could not read '$2' from $1"
    echo "$v"
}

drain_of() { local v; v="$(sed -nE 's/^ *Drain +([0-9]+).*/\1/p' "$1" | head -1)"; echo "${v:-0}"; }

has() { grep -qF "$2" "$1"; }   # fixed string in a dump

bad() { echo "FAIL: $*"; CHECK_FAIL=1; }

want_saves() { # <before sheet> <after sheet> <levels lost> <what>
    local k
    for k in Fortitude Reflex Will; do
        b="$(num "$1" $k)"; a="$(num "$2" $k)"
        [ "$a" -eq $((b - $3)) ] || bad "$4: $k is $a, wanted $b-$3 = $((b - $3))."
    done
}

# ---- A. level 2 lives ------------------------------------------------------------------
echo "A. level 2"
run alignment-drain-level2 alignment-drain-wield-once.keys
check_screens '*'
check_expect "Class  Warrior 2" "the loaded character is the level 2 fixture"
has "$(dump wield-prompt)" "uneasy"        || bad "A: the wield did not print 'uneasy'."
has "$(dump wield-prompt)" "Die? [yn]"     && bad "A: a level 2 character was asked to die."
B="$(dump sheet-0-baseline)"; F="$(dump sheet-1-after)"
echo "  XP $(num "$B" XP) -> $(num "$F" XP), Drain $(drain_of "$B") -> $(drain_of "$F")"
[ "$(num "$F" XP)" -eq 0 ]           || bad "A: effective XP is $(num "$F" XP), wanted 0."
[ "$(drain_of "$F")" -eq 1000 ]      || bad "A: drained XP is $(drain_of "$F"), wanted 1000."
want_saves "$B" "$F" 1 "A"

# ---- B. level 1 is asked to die ----------------------------------------------------------
echo "B. level 1"
run alignment-drain-level1 alignment-drain-wield-once.keys
check_screens '*'
W="$(dump wield-prompt)"
has "$W" "uneasy"    || bad "B: the wield did not print 'uneasy'."
has "$W" "You die... Die? [yn]" || bad "B: a level 1 wrong-alignment wielder was not asked to die."

# ---- C, D. balance rule, Lawful Neutral --------------------------------------------------
echo "C. balance weapon, Lawful Neutral"
run alignment-drain-lawful-neutral alignment-drain-balance.keys
check_screens '*'
check_expect "Quality added" "the balance quality was stamped"
W="$(dump wielded)"
has "$W" "uneasy"    && bad "C: a Lawful Neutral wielder of a balance weapon was told 'uneasy'."
has "$W" "Die? [yn]" && bad "C: a Lawful Neutral wielder of a balance weapon was drained to death."
B="$(dump sheet-0-baseline)"; F="$(dump sheet-1-wielded)"
want_saves "$B" "$F" 0 "C"
[ "$(drain_of "$F")" -eq 0 ] || bad "C: drained XP is $(drain_of "$F"), wanted 0."

echo "D. control: chaotic weapon, Lawful Neutral"
run alignment-drain-lawful-neutral alignment-drain-chaotic-control.keys
check_screens '*'
check_expect "Quality added" "the chaotic quality was stamped"
W="$(dump wielded)"
has "$W" "uneasy"    || bad "D: a Lawful wielder of a chaotic weapon was not told 'uneasy'."
has "$W" "Die? [yn]" || bad "D: the level 1 Lawful wielder of a chaotic weapon was not asked to die."

# ---- E. balance rule, Chaotic Good -------------------------------------------------------
echo "E. balance weapon, Chaotic Good level 5"
run alignment-drain-warrior alignment-drain-balance.keys
check_screens '*'
check_expect "Quality added" "the balance quality was stamped"
has "$(dump wielded)" "uneasy" || bad "E: a Chaotic Good wielder of a balance weapon was not told 'uneasy'."
B="$(dump sheet-0-baseline)"; F="$(dump sheet-1-wielded)"
want_saves "$B" "$F" 2 "E"
[ "$(drain_of "$F")" -gt 0 ] || bad "E: no drained XP after wielding the balance weapon."

check_done "level 2 lives at 0 XP, level 1 is asked to die, and the balance rule drains Chaotic Good but not Lawful Neutral"
