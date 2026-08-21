#!/bin/bash
# Regression check for the multiclass experience penalty in
# Character::XPPenalty (src/Create.cpp), bd inc-by8.
#
# WHAT WAS WRONG. The function asked whether the character's HIGHEST class was
# one his race favours, and charged a flat 25% of all experience when it was
# not. Three separate things follow from that, and all three are wrong.
#
#   - A favoured class that is not the highest one counted for nothing. A
#     dwarf Fighter 7 / Cleric 2 -- the Player's Handbook's own worked example,
#     which is supposed to cost nothing -- paid.
#   - A prestige class carries CF_FAVOURED, the flag that says the class counts
#     as favoured for everybody. It was honoured only while that class was also
#     the highest, and a prestige class can never be the highest, because its
#     entry requirements guarantee core levels beneath it. So every prestige
#     character paid from the level he entered the class, against the wording
#     of his own class description.
#   - The manual said 20% and the code took 25%.
#
# THE RULE NOW. Every class the race favours leaves the comparison, and so does
# every prestige class. Of the classes that are left, each one standing two or
# more levels below the highest of them costs 20%, and those costs add. One
# class left, or none, costs nothing. Removing ALL of the race's favoured
# classes rather than the single one D&D grants is Brian's ruling: Incursion
# gives each race two and the Wood Elf three, and D&D assumes a party where
# Incursion sends the player in alone.
#
# THE ORACLE is the sheet's Basics block. src/Sheet.cpp:62-67 prints a
# " Penal <n>%" line when the penalty is positive and prints nothing at all
# when it is zero, so the absence of the line reads as clearly as its presence.
# Every figure below was read off a character sheet.
#
# THE SIX CHARACTERS, and what each one is for. The first four are one Elf
# photographed four times as he gains levels; a standard Elf favours Mage and
# Ranger (lib/races.irh:967), so Barbarian, Rogue and Warrior are all counted.
#
#   Elf Barbarian 3                  THE CONTROL. One counted class, so there
#     xp-penalty-rule.keys, xpa      is nothing to compare it against. He must
#                                    read the same on both sides. Without him
#                                    a build that had simply stopped charging
#                                    anybody would still pass three of the
#                                    other five cases.
#
#   Elf Barbarian 3 / Rogue 1        THE MEASUREMENT. The rogue stands two
#     xp-penalty-rule.keys, xpb      levels below the barbarian: 20%.
#
#   Elf Barbarian 3 / Rogue 1 /      THE STACKING. Two classes stand two below
#   Warrior 1                        the barbarian, so the costs add to 40%.
#     xp-penalty-rule.keys, xpc      The old flat figure could not produce 40
#                                    at all, and a fix that read the rule as
#                                    one flat penalty would stop at 20 here.
#
#   Elf Barbarian 3 / Rogue 2 /      WITHIN ONE LEVEL. Every counted class is
#   Warrior 2                        now within one level of the highest, so
#     xp-penalty-rule.keys, xpd      nothing is owed.
#
#   Elf Rogue 5 / Assassin 2         THE PRESTIGE CASE. The assassin is a
#     prestige-assassin.keys         prestige class and leaves the comparison,
#                                    which leaves the rogue alone and nothing
#                                    to pay. This character is borrowed from
#                                    tools/check_stacked_abilities.sh.
#
#   Wood Elf Rogue 2 / Warrior 1     THE SECOND WITHIN-ONE-LEVEL CASE, at the
#     xp-penalty-crash.keys          smallest size the rule has, and a
#                                    different race. Wood elves favour
#                                    Barbarian, Ranger and Druid
#                                    (lib/subraces.irh:498), so both classes
#                                    are counted and they are one level apart.
#                                    Borrowed from tools/check_xp_penalty.sh,
#                                    which checks that same run for the
#                                    segfault of bd inc-5y8.
#
# Measured on builds differing only in src/Create.cpp:
#                                        before      after
#   Elf Barbarian 3                      none        none
#   Elf Barbarian 3 / Rogue 1            25%         20%
#   Elf Barbarian 3 / Rogue 1 / War 1    25%         40%
#   Elf Barbarian 3 / Rogue 2 / War 2    25%         none
#   Elf Rogue 5 / Assassin 2             25%         none
#   Wood Elf Rogue 2 / Warrior 1         25%         none
#
# Humans are not here on purpose. They have no favoured list at all
# (lib/races.irh:195-206) and are exempt by CA_VERSATILITY instead, which is a
# different rule in a different branch of the same function and is not what
# this checks.
#
# Usage: tools/check_xp_penalty_rule.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

fail=0

# Play one key script and print the directory it left behind.
run_keys () { # <keyscript> <seed>
    local out
    out="$(tools/headless.sh "$1" "$2" 2>&1)"
    printf '%s\n' "$out" | awk '/^run:/ {print $2}'
}

# $1 dump file, $2 guard string, $3 what the Penal line must say, or "-" for
# "the sheet must carry no Penal line at all", $4 what this character is called
check_penalty () {
    local dump="$1" guard="$2" want="$3" who="$4"

    if [ ! -f "$dump" ]; then
        echo "INCONCLUSIVE: $who -- no character sheet was written to $dump,"
        echo "              so the key script has rotted. Nothing was measured."
        fail=1; return
    fi
    # The guard first. A key script that stops producing the character must
    # read as rotted, not as a passing test: a sheet for somebody else, or a
    # sheet with the wrong levels on it, measures the wrong rule.
    if ! grep -q "$guard" "$dump"; then
        echo "INCONCLUSIVE: $who -- \"$guard\" is not on the sheet, so the key"
        echo "              script no longer builds him. Nothing was measured."
        echo "              dump: $dump"
        fail=1; return
    fi
    if [ "$want" = "-" ]; then
        if grep -q "Penal" "$dump"; then
            echo "FAIL: $who must owe nothing, and his sheet says:"
            grep -n "Penal" "$dump" | sed 's/^/      /'
            fail=1; return
        fi
    else
        if ! grep -q "Penal $want%" "$dump"; then
            echo "FAIL: $who must owe $want%, and his sheet says:"
            grep -n "Penal" "$dump" | sed 's/^/      /' || echo "      no Penal line at all"
            fail=1; return
        fi
    fi
}

# The Elf who holds every shape of the rule. One session, four sheets.
RULE="$(run_keys tools/keys/xp-penalty-rule.keys 1)"
check_penalty "$RULE/logs/screens/0001-xpa.txt" "Class  Barbarian 3" "-" \
              "Elf Barbarian 3"
check_penalty "$RULE/logs/screens/0002-xpb.txt" "Rogue 1"            "20" \
              "Elf Barbarian 3 / Rogue 1"
check_penalty "$RULE/logs/screens/0003-xpc.txt" "Warrior 1"          "40" \
              "Elf Barbarian 3 / Rogue 1 / Warrior 1"
check_penalty "$RULE/logs/screens/0004-xpd.txt" "Warrior 2"          "-" \
              "Elf Barbarian 3 / Rogue 2 / Warrior 2"

# The prestige case.
ASSN="$(run_keys tools/keys/prestige-assassin.keys 1)"
check_penalty "$ASSN/logs/assn.txt" "Assassin 2" "-" "Elf Rogue 5 / Assassin 2"

# The smallest within-one-level case, on a race with three favoured classes.
CRASH="$(run_keys tools/keys/xp-penalty-crash.keys 7)"
WOOD="$(ls "$CRASH"/logs/screens/*-crashed.txt 2>/dev/null | head -1)"
check_penalty "${WOOD:-$CRASH/logs/screens/missing-crashed.txt}" "Warrior 1" \
              "-" "Wood Elf Rogue 2 / Warrior 1"

if [ "$fail" = 0 ]; then
    echo "PASS: favoured and prestige classes leave the comparison, and each"
    echo "      class two levels below the rest costs 20% on top of the last"
else
    echo "FAIL: tools/check_xp_penalty_rule.sh"
fi
exit "$fail"
