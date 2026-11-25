#!/bin/bash
# gate: live
# Does a specialist wizard casting an opposed-school spell lose fatigue with a
# chance equal to the school penalty, not double it? (bd inc-qple2)
#
# THE RULE (src/Magic.cpp, Creature::Cast; the design comment in
# Creature::getSpellMana, "New rule -- specialist wizards suffer more"). When
# the cast spell's best school has a negative SpecialistTable entry, the cast
# drains 1 fatigue with chance equal to that penalty, in percent. The code
# rolled random(100) < abs(specMod*2), twice the stated chance.
#
# THE CHARACTER is a Thaumaturge; Magic Missile is Evocation, a -10 school for
# him (SpecialistTable[Thaumaturge][Evocation]). The chance is 10, so the drain
# happens exactly when the roll is below 10. The old code drained below 20.
#
# THE TEST. INCURSION_SPEC_DRAIN_ROLL=<0..99> replaces the drain roll. Two
# sessions cast Magic Missile once (tools/keys/spec-drain-cast.keys):
#   roll 9:  "Lacking aptitude" appears and FP falls by exactly 1   (9 < 10)
#   roll 10: no message and FP is unchanged                         (10 is not < 10)
# Old code at roll 10 drains (10 < 20), so the second session goes red.
# Both sessions must spend the same mana, 2 (base 1, +100% for the -10 penalty);
# this guards that the mana price did not change. The mana and FP figures are
# read from the status line ("Mana:30/32 FP:7/8") of the before and after dumps.
#
# THE GUARD. A session whose cast spent no mana never cast, so it is
# INCONCLUSIVE (exit 2), never a pass. A run with no gameplay is exit 2 too
# (check_lib).
#
# fact: character -- fixture orc-thaumaturge-seed1-opt0822 (INCURSION_LOAD)
# fact: settings -- CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: the drain roll -- INCURSION_SPEC_DRAIN_ROLL
# fact: spell-failure roll -- wizard-mode switch Ignore Spell Failure (tools/keys/spec-drain-cast.keys)
# fact: target of the bolt -- none needed; the key script aims east at whatever square is there, and neither figure read depends on a hit
# fact: starting fatigue and mana -- read from the before dump of each session, not assumed
# fact: other fatigue changes during the cast turn -- none seen; FP starts at its maximum so regeneration cannot show, and the roll-10 session proves no other drain
#
# Usage: tools/check_spec_drain_rate.sh [--prove-red]   exit 0 pass, 1 fail, 2 inconclusive
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The old doubled chance: roll 10 drains.
check_mutation src/Magic.cpp \
    '        if (SpecDrainRoll() < abs(specMod)) {' \
    '        if (SpecDrainRoll() < abs(specMod*2)) {'

export INCURSION_LOAD=orc-thaumaturge-seed1-opt0822

FAIL=0
# fig <screen> <field> <which>: prints the current (1) or maximum (2) of Mana or FP.
fig() {
    grep -o "$2:[0-9]*/[0-9]*" "$1" | head -1 | sed "s/.*://" | cut -d/ -f"$3"
}

# run_roll <roll> <want>: want is drain or none. Sets SPENT.
run_roll() {
    local roll="$1" want="$2" b a fb fa msg ok=ok
    INCURSION_SPEC_DRAIN_ROLL="$roll" check_run tools/keys/spec-drain-cast.keys 1 > /dev/null
    local D="$CHECK_RUN/logs/screens"
    b="$(ls "$D"/*-before.txt 2>/dev/null | head -1)"
    a="$(ls "$D"/*-after.txt 2>/dev/null | head -1)"
    [ -n "$b" ] && [ -n "$a" ] || _check_die 2 "roll $roll wrote no before/after dump in $D."
    local mb ma
    mb="$(fig "$b" Mana 1)"; ma="$(fig "$a" Mana 1)"
    fb="$(fig "$b" FP 1)"; fa="$(fig "$a" FP 1)"
    [ -n "$mb" ] && [ -n "$ma" ] && [ -n "$fb" ] && [ -n "$fa" ] || _check_die 2 \
        "roll $roll: could not read Mana and FP from $b and $a."
    [ "$fb" -gt 0 ] || _check_die 2 "roll $roll: FP was 0 before the cast, so a drop cannot show."
    SPENT=$((mb - ma))
    [ "$SPENT" -gt 0 ] || _check_die 2 "roll $roll: the cast spent no mana, so no cast happened."
    if grep -q "Lacking aptitude" "$a"; then msg=yes; else msg=no; fi
    if [ "$want" = drain ]; then
        [ "$msg" = yes ] && [ $((fb - fa)) -eq 1 ] || ok=FAIL
    else
        [ "$msg" = no ] && [ "$fb" -eq "$fa" ] || ok=FAIL
    fi
    [ "$ok" = ok ] || FAIL=1
    printf '  roll %-2s  mana spent %s  FP %s -> %s  message %-3s  want %-5s  %s\n' \
        "$roll" "$SPENT" "$fb" "$fa" "$msg" "$want" "$ok"
}

run_roll 9 drain;  S9=$SPENT
run_roll 10 none;  S10=$SPENT

echo
if [ "$S9" -ne "$S10" ]; then
    echo "FAIL: the cast cost $S9 mana at roll 9 and $S10 at roll 10; the mana price must not depend on the drain roll"
    exit 1
fi
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: the drain did not happen exactly when the roll is below the school penalty, 10 (inc-qple2)"
    exit 1
fi
echo "PASS: a Thaumaturge's Evocation cast drains fatigue exactly below 10 (the penalty), mana spent $S9 both times"
exit 0
