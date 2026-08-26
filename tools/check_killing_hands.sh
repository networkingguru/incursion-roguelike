#!/bin/bash
# Regression check for PA-08-F25 / inc-tek.8.8: Bracers of Killing Hands pay
# two points per magical plus to unarmed hit rolls and unarmed damage.
#
# WHAT WAS WRONG. Both grants in lib/m_items.irh used pval PLUS_1PER1 although
# the item's own Desc promises two points per plus.
#
# THE ORACLE is the character sheet's Brawl block. src/Sheet.cpp:175-190 prints
# KAttr[A_HIT_BRAWL] and KAttr[A_DMG_BRAWL], including each source beside it.
# Wizard acquisition makes and Auto-Identifies a known +2 pair; the inventory
# dump proves that plus, and the sheet must print +4 for both Brawl attributes.
#
# MEASURED, seed 1, Bracers of Killing Hands +2:
#   BEFORE: item plus +2; Brawl +toHit +2; Brawl Damage +2
#   AFTER:  item plus +2; Brawl +toHit +4; Brawl Damage +4
#
# Usage: tools/check_killing_hands.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/killing-hands.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

if echo "$out" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing."
    echo "$out"
    exit 1
fi
if echo "$out" | grep -q "the key script looked for something"; then
    echo "FAIL: the key script did not find a screen it expected."
    echo "$out"
    exit 1
fi

inventory="$run/logs/screens/0001-inventory.txt"
sheet="$run/logs/screens/0002-sheet.txt"
for f in "$inventory" "$sheet"; do
    [ -f "$f" ] || { echo "FAIL: no measurement screen at $f"; exit 1; }
done

item_line="$(grep -F "Bracers +" "$inventory" | grep -F "of Killing Hands" | head -1)"
item_plus="$(echo "$item_line" | sed -n 's/.*Bracers +\([0-9][0-9]*\) of Killing Hands.*/\1/p')"
[ -n "$item_plus" ] || {
    echo "FAIL: inventory does not prove identified Bracers of Killing Hands and their plus."
    exit 1
}

brawl="$(awk '/^ Brawl /{f=1} /^ Melee /{f=0} f' "$sheet")"
[ -n "$brawl" ] || {
    echo "FAIL: the sheet has no Brawl block, so this run proved nothing."
    exit 1
}
got_hit="$(echo "$brawl" | sed -n '/+toHit/s/.*+\([0-9][0-9]*\) magic.*/\1/p')"
got_damage="$(echo "$brawl" | sed -n '/Damage/s/.*+\([0-9][0-9]*\) magic.*/\1/p')"
want=$((2 * item_plus))

echo "Killing Hands item plus: +$item_plus"
echo "Brawl +toHit magic bonus: +${got_hit:-<none>}"
echo "Brawl Damage magic bonus: +${got_damage:-<none>}"

fail=0
if [ "$item_plus" -ne 2 ]; then
    echo "FAIL: expected the scripted item to be +2."
    fail=1
fi
if [ "${got_hit:-}" != "$want" ]; then
    echo "FAIL: Brawl +toHit magic bonus is +${got_hit:-<none>}; expected 2 x +$item_plus = +$want."
    fail=1
fi
if [ "${got_damage:-}" != "$want" ]; then
    echo "FAIL: Brawl Damage magic bonus is +${got_damage:-<none>}; expected 2 x +$item_plus = +$want."
    fail=1
fi

[ "$fail" -eq 0 ] && echo "PASS: Killing Hands pays two Brawl hit and damage points per plus."
exit "$fail"
