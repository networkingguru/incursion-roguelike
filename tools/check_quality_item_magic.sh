#!/bin/bash
# gate: live
# Does a +0 weapon that carries a quality count as magical? (bd inc-rgzr, instance 3)
#
# THE DEFECT. Item::isMagic (inc/Item.h) is `eID || Plus` and is NOT virtual.
# Weapon and Armour declare their own isMagic, which also counts a quality
# (src/Item.cpp), but every caller holds an Item*, so the override never runs.
# A flaming +0 long sword with no effect id is therefore "mundane".
#
# THE ORACLE is a rule that branches on isMagic and shows its result: when a
# blob's A_DEQU acid has no save DC, src/Fight.cpp sets
#   e2.ignoreHardness = (e2.saveDC <= 0 && !it->isMagic());
# so a mundane sword is melted and a magical one is not. The weapon's own
# description page states its hit points (see tools/check_dequ_magic_hardness.sh).
#
# THREE SESSIONS, same character, same seed, same blobs:
#   subject  tools/keys/quality-item-magic.keys: a long sword, Plus 0, stamped
#            WQ_FLAMING by wizard mode. MUST keep its 15 hit points.
#   control  tools/keys/dequ-hardness-plain.keys: the same sword, no quality.
#            MUST lose hit points (mundane before and after the fix).
#   control  tools/keys/dequ-hardness-magic.keys: a Holy Avenger.
#            MUST keep 38 of 35 (magical before and after the fix).
# A control that misbehaves, or a subject that never took acid on the sword, or
# a sword that is not flaming at 15 of 15 at the start, exits 2.
#
# Usage: tools/check_quality_item_magic.sh    (0 pass, 1 fail, 2 could not measure)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

screen() { # <glob> -> first matching screen of the current run, or exit 2
    local f
    f="$(ls "$CHECK_RUN"/logs/screens/$1 2>/dev/null | head -1)"
    [ -n "$f" ] || _check_die 2 "no screen $1 in $CHECK_RUN"
    echo "$f"
}
need() { # <file> <literal> <why>: exit 2 when the literal is absent
    grep -qF -- "$2" "$1" || _check_die 2 "$3: no \"$2\" in $1"
}

echo "--- control: a plain long sword is melted ---"
check_run tools/keys/dequ-hardness-plain.keys 5
need "$(screen '*-plain-before.txt')" "It has 15 out of 15 hit" "control sword not at full hit points"
need "$(screen '*-plain-strike-1.txt')" "splashes the long sword" "control sword never took acid"
after="$(screen '*-plain-after.txt')"
if grep -qF "It has 15 out of 15 hit" "$after"; then
    _check_die 2 "control misbehaves: the plain sword kept its hit points ($after)"
fi
echo "  ok    the plain sword lost hit points"

echo "--- control: a Holy Avenger keeps its hit points ---"
check_run tools/keys/dequ-hardness-magic.keys 5
need "$(screen '*-magic-strike-1.txt')" "splashes the Long Sword, Holy Avenger" "control sword never took acid"
after="$(screen '*-magic-after.txt')"
need "$after" "It has 38 out of 35 hit" "control misbehaves: the Holy Avenger lost hit points"
echo "  ok    the Holy Avenger kept 38 of 35"

echo "--- subject: a +0 flaming long sword ---"
check_run tools/keys/quality-item-magic.keys 5
before="$(screen '*-quality-before.txt')"
need "$before" "Uncursed Flaming Long Sword" "subject is not a flaming long sword"
need "$before" "It has 15 out of 15 hit" "subject not at full hit points"
if grep -qE "Long Sword, .*[+-][0-9]" "$before"; then
    _check_die 2 "subject carries a plus; it must be +0 ($before)"
fi
need "$(screen '*-quality-strike-1.txt')" "splashes the flaming long sword" "subject never took acid"
after="$(screen '*-quality-after.txt')"
if grep -qF "It has 15 out of 15 hit" "$after"; then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    the flaming sword kept its hit points: isMagic says magical"
else
    CHECK_FAIL=1
    echo "  FAIL  the +0 flaming sword lost hit points: isMagic says mundane ($after)"
    grep -hF "It has" "$after"
fi

check_done "a +0 weapon with a quality counts as magical"
