#!/bin/bash
# Regression check for bd inc-i9q.3: getting hungrier must never make a
# character stronger.
#
# WHAT WAS WRONG. src/Values.cpp switches on HungerState() and the Hungry arm
# had no break, so it fell into the Starving arm and a Hungry character paid
# BOTH penalties. Hungry cost STR -3, CON -3 and FAT -3 where Starving cost
# only -2 of each. A player who let his character go from Hungry to Starving
# watched three attributes go UP.
#
# THE ORACLE is the sidebar, which prints the hunger state as a word and the
# seven attributes as numbers, side by side, on every frame. The key script
# tools/keys/hunger-penalty.keys photographs the same character three times:
# fed, Hungry, and Starving. Nothing else about him changes in between.
#
# MEASURED, seed 1, Dragonkin barbarian:
#
#                BEFORE              AFTER
#   Satiated     STR 16  CON 15      STR 16  CON 15
#   Hungry       STR 13  CON 12      STR 15  CON 14
#   Starving     STR 14  CON 13      STR 14  CON 13
#
# THE RULE THIS ENFORCES is the ordering, not the three numbers. Hunger must
# cost something, and Starving must cost at least as much as Hungry. A build
# that stopped charging anybody would fail the first test; a build that
# reintroduced the fallthrough would fail the second.
#
# Usage: tools/check_hunger_penalty.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/hunger-penalty.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

# A session that measured nothing must never read as a pass: that mistake is
# inc-loa.3.
if echo "$out" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map"
    exit 1
fi

# Read one attribute off one photograph. The sidebar line reads "STR: 16".
attr() {  # attr <screen> <STR|CON>
    grep -o "$2: *[0-9][0-9]*" "$1" | grep -o '[0-9][0-9]*$' | head -1
}

fed="$run/logs/screens/0001-fed.txt"
hungry="$run/logs/screens/0002-hungry.txt"
starving="$run/logs/screens/0003-starving.txt"

for f in "$fed" "$hungry" "$starving"; do
    if [ ! -f "$f" ]; then
        echo "FAIL: missing screen dump $f"
        echo "$out"
        exit 1
    fi
done

# The state words are what make the three photographs mean anything. The key
# script already stops on them, and this repeats the test so that a script
# edited out of step with this file cannot quietly compare three fed frames.
grep -q "Satiated" "$fed"  || { echo "FAIL: the first photograph is not of a fed character"; exit 1; }
grep -q "Hungry"   "$hungry"   || { echo "FAIL: the second photograph is not of a Hungry character"; exit 1; }
grep -q "Starving" "$starving" || { echo "FAIL: the third photograph is not of a Starving character"; exit 1; }

fail=0
printf '%-10s %s %s\n' "state" "STR" "CON"
for pair in "Satiated:$fed" "Hungry:$hungry" "Starving:$starving"; do
    state="${pair%%:*}"; file="${pair#*:}"
    printf '%-10s %3s %3s\n' "$state" "$(attr "$file" STR)" "$(attr "$file" CON)"
done
echo

for a in STR CON; do
    f="$(attr "$fed" "$a")"
    h="$(attr "$hungry" "$a")"
    s="$(attr "$starving" "$a")"
    if [ -z "$f" ] || [ -z "$h" ] || [ -z "$s" ]; then
        echo "FAIL: could not read $a off all three photographs"
        fail=1
        continue
    fi
    if [ "$h" -ge "$f" ]; then
        echo "FAIL: $a is $h when Hungry and $f when fed. Hunger must cost something."
        fail=1
    fi
    if [ "$s" -gt "$h" ]; then
        echo "FAIL: $a is $h when Hungry and $s when Starving. Getting hungrier"
        echo "      made him stronger, which is inc-i9q.3 come back."
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "PASS: hunger costs, and starving costs at least as much as hunger."
fi
exit "$fail"
