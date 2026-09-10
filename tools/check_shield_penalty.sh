#!/bin/bash
# Does a shield's armour check penalty come from the shield? Bead inc-rsps.
#
# THE DEFECT. Armour::PenaltyVal (src/Item.cpp:2147) had two paths. Body
# armour returned the item's own authored Penalty:. A shield never read its
# Penalty: at all; it read a ladder of size comparisons, so every shield of a
# size cost the same, the data had no say, and the ladder's -10 rung was dead
# because the line below it repeated the test that selected -10 and doubled
# it. Measured on 2026-09-08: buckler 0, small shield -2, kite shield -6,
# tower shield -18, against SRD figures of -1, -1, -2 and -10.
#
# WHAT THE GAME NOW OWES A MEDIUM CHARACTER is what lib/weapons.irh authors:
# buckler -1, small shield -2, kite shield -4, tower shield -10. Brian chose
# that ramp on 2026-09-09. It is not the SRD's -1/-1/-2/-10 and is not meant
# to be; the SRD is the floor the old numbers were three times over, not the
# target.
#
# THE ORACLE is the character dump the sheet's [W] command writes, read twice
# for every shield and never from a screen:
#   the Skill Ratings block   "Balance -7 (0 ranks, +3 DEX, -10 armour)"
#   the Movement Rate line    "x 75% shield", which A_MOV builds from the same
#                             penalty at 100% + 5% * (penalty/2)
# The two are independent consumers of PenaltyVal (src/Create.cpp:4278 and
# src/Values.cpp:914), so a fix that satisfies one and not the other fails
# here rather than passing.
#
# THE SIZE STEP is read separately, on a halfling, by the second session
# below. The authored figure is what a MEDIUM character pays; a bearer one
# size smaller carries relatively more shield and pays double.
#
# NOT COVERED, and say so rather than let the check imply it:
#   * a bearer LARGER than Medium, who halves these figures. No playable race
#     is one.
#   * the kite and tower shields in a Small hand. The game will not put them
#     there, so there is nothing to read.
#   * the giant shield, which is IT_NOGEN and never reaches a hand.
#   * whether these magnitudes are the right ones. This check defends the
#     numbers that were chosen, not the choice.
#
# Usage: tools/check_shield_penalty.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=4

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# $1 key script, $2 the name this check calls it. Echoes the run directory.
run_session() {
    local out r
    out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
           tools/headless.sh "$1" "$SEED" 2>&1)"
    r="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q "the key script looked for something"; then
        echo "INCONCLUSIVE: the $2 key script could not find something on" >&2
        echo "              screen. Run: $r" >&2
        exit 2
    fi
    [ -n "$r" ] || { echo "INCONCLUSIVE: no run directory for $2." >&2; exit 2; }
    echo "$r"
}

run="$(run_session tools/keys/shield-penalty.keys Medium)"

rc=0

# Every reading is worthless unless the named shield was the one in the hand,
# so read the slot line back before reading any number.
in_hand() {   # $1 screen basename, $2 the item name the slot must show
    local f="$run/logs/screens/$1"
    [ -f "$f" ] || {
        echo "INCONCLUSIVE: no screen at $f"
        exit 2
    }
    grep -q "Ready Hand   :$2" "$f" || {
        echo "INCONCLUSIVE: the Ready Hand does not hold a $2, so this run"
        echo "              measured something else. Screen: $f"
        exit 2
    }
}

dump() {      # $1 dump basename -- echoes the path
    local f="$run/logs/$1.txt"
    [ -f "$f" ] || { echo "INCONCLUSIVE: no character dump at $f" >&2; exit 2; }
    echo "$f"
}

# $1 dump name, $2 shield as the reader knows it, $3 the armour term owed
armour_term() {
    local f term
    f="$(dump "$1")"
    term="$(sed -n 's/.*Balance  *[-+][0-9]*  *(0 ranks, +3 DEX, \(-[0-9]*\) armour).*/\1/p' "$f")"
    if [ -z "$term" ]; then
        echo "FAIL: the $2 puts no armour term on Balance at all. It must cost"
        echo "      $3. Dump: $f"
        rc=1
        return
    fi
    if [ "$term" != "$3" ]; then
        echo "FAIL: the $2 costs $term to Balance, and it must cost $3."
        echo "      Dump: $f"
        rc=1
    fi
}

# $1 dump name, $2 shield as the reader knows it, $3 the shield factor owed,
# or the word "none" when the penalty is too small to move the rate.
move_factor() {
    local f factor
    f="$(dump "$1")"
    factor="$(sed -n 's/.*x \([0-9]*%\) shield.*/\1/p' "$f")"
    if [ "$3" = none ]; then
        [ -z "$factor" ] || {
            echo "FAIL: the $2 slows the character by $factor, and a penalty"
            echo "      that small must not reach the movement rate at all."
            echo "      Dump: $f"
            rc=1
        }
        return
    fi
    if [ "$factor" != "$3" ]; then
        echo "FAIL: the $2 leaves a movement factor of '${factor:-none}',"
        echo "      and it must be $3. Dump: $f"
        rc=1
    fi
}

### The baseline. Nothing is in the hand, so nothing may be charged for.

base="$(dump none)"
if grep -q "shield" <(grep "x .*skill" "$base"); then
    echo "FAIL: a character with an empty Ready Hand is paying a shield's"
    echo "      movement penalty. Dump: $base"
    rc=1
fi
if grep -q "Balance" "$base"; then
    echo "FAIL: the baseline character has an armour term on Balance, so every"
    echo "      reading below is of a shield plus something else. Dump: $base"
    rc=1
fi

### Each shield, in the hand, one at a time.

in_hand 0001-kite-in-hand.txt    "kite shield"
in_hand 0002-small-in-hand.txt   "small shield"
in_hand 0003-buckler-in-hand.txt "buckler"
in_hand 0004-tower-in-hand.txt   "tower shield"

armour_term buck  "buckler"      -1
armour_term small "small shield" -2
armour_term kite  "kite shield"  -4
armour_term tower "tower shield" -10

move_factor buck  "buckler"      none
move_factor small "small shield" 95%
move_factor kite  "kite shield"  90%
move_factor tower "tower shield" 75%

### THE SIZE STEP. The same shields, one size of bearer down.

run="$(run_session tools/keys/shield-penalty-small.keys Small)"

in_hand 0001-buckler-in-hand.txt "buckler"
in_hand 0002-small-in-hand.txt   "small shield"

# The halfling's own studded leather is summed into the Skill Ratings armour
# term, so only the movement line reads the shield on its own. A Small bearer
# owes double the authored figure: buckler -2 (95%), small shield -4 (90%).
move_factor buck  "buckler on a halfling"      95%
move_factor small "small shield on a halfling" 90%

if [ "$rc" = 0 ]; then
    echo "  ok: buckler -1, small shield -2, kite shield -4, tower shield -10"
    echo "      to a Medium character's skills, the movement rate agrees, and"
    echo "      a Small bearer pays double"
fi
exit $rc
