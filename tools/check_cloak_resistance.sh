#!/bin/bash
# Regression check for PA-08-F33 / inc-tek.8.8: a Cloak of Resistance grants
# a resistance bonus, not a plain magic bonus.
#
# THE RULE. The cloak promises a resistance bonus equal to its magical plus.
# Its grant used ADJUST, so a +3 cloak contributed "+3 magic" and stacked with
# auspicious +2 armour's resistance bonus. ADJUST_RES makes both grants the
# same type, and AddBonus keeps only the larger bonus of a type.
#
# THE ORACLE is the character sheet's three saving-throw totals and their
# named terms, in two arms of one seed-1 session. Measured before the fix:
# cloak +3 alone was Fort/Ref/Will 6/4/6 ("+3 magic"); cloak plus auspicious
# armour +2 was 8/6/8 ("+3 magic, +2 resistance"). After the fix, cloak alone
# remains 6/4/6 but names "+3 resistance", and both items are also 6/4/6:
# only the larger resistance bonus counts.
#
# Usage: tools/check_cloak_resistance.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/cloak-resistance.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

if echo "$out" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing."
    echo "$out"
    exit 1
fi
if echo "$out" | grep -q "the key script looked for something"; then
    echo "FAIL: the key script missed a screen it expected; read $run/logs/screens."
    exit 1
fi

alone="$run/logs/screens/0002-cloak-alone.txt"
both_inv="$run/logs/screens/0003-both-inventory.txt"
both="$run/logs/screens/0004-cloak-and-armour.txt"
for f in "$alone" "$both_inv" "$both"; do
    [ -f "$f" ] || { echo "FAIL: no screen dump at $f"; exit 1; }
done

for f in "$alone" "$both"; do
    for save in Fortitude Reflex Will; do
        grep -q "^ $save " "$f" || {
            echo "FAIL: $f does not show the $save saving-throw line."
            exit 1
        }
    done
done
grep -q "auspicious orcish hide armour +2" "$both_inv" || {
    echo "FAIL: the second arm does not show auspicious +2 armour."
    exit 1
}

save_number() {
    awk -v save="$2" '$1 == save {gsub(/\+/, "", $2); print $2}' "$1"
}

alone_fort="$(save_number "$alone" Fortitude)"
alone_ref="$(save_number "$alone" Reflex)"
alone_will="$(save_number "$alone" Will)"
both_fort="$(save_number "$both" Fortitude)"
both_ref="$(save_number "$both" Reflex)"
both_will="$(save_number "$both" Will)"

echo "Cloak plus: +3"
echo "Auspicious armour bonus: +2 resistance"
echo "Cloak alone saves (Fortitude/Reflex/Will): $alone_fort/$alone_ref/$alone_will"
echo "Cloak plus armour saves (Fortitude/Reflex/Will): $both_fort/$both_ref/$both_will"
echo "Cloak alone readout: $(grep '^ Fortitude ' "$alone")"
echo "Cloak plus armour readout: $(grep '^ Fortitude ' "$both")"

fail=0
if [ "$alone_fort/$alone_ref/$alone_will" != "6/4/6" ]; then
    echo "FAIL: changing the bonus type must not change the cloak-alone control (6/4/6)."
    fail=1
fi
if [ "$both_fort/$both_ref/$both_will" != "6/4/6" ]; then
    echo "FAIL: the +3 cloak and +2 auspicious armour stack; only +3 should count."
    fail=1
fi
if ! grep -q "+3 resistance" "$alone"; then
    echo "FAIL: the cloak-alone readout does not name its +3 as resistance."
    fail=1
fi
if grep -q "+[0-9][0-9]* magic" "$alone"; then
    echo "FAIL: the cloak-alone readout still names a magic saving-throw bonus."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: cloak alone is unchanged, and auspicious armour no longer stacks."
fi
exit "$fail"
