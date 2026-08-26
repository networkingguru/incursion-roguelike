#!/bin/bash
# Regression check for F37 / inc-tek.8.8: a Sunblade grants the mild cold
# resistance its page promises, at PLUS_1PER1 alongside its strong PLUS_2PER1
# resistance to life-draining.
#
# THE ORACLE is the character sheet's Cold and Life Drain resistance before and
# after a known +2 Sunblade is wielded, plus its activation menu before and after
# use. Wielding must add 2 Cold and 4 Life Drain; activation must spend one use.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/sunblade-cold.keys

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

before="$run/logs/screens/0001-without-sunblade.txt"
inventory="$run/logs/screens/0002-wielded.txt"
activation="$run/logs/screens/0003-activation-menu.txt"
activated="$run/logs/screens/0004-after-activation.txt"
activation_after="$run/logs/screens/0005-activation-menu-after.txt"
after="$run/logs/screens/0006-with-sunblade.txt"
for f in "$before" "$inventory" "$activation" "$activated" "$activation_after" "$after"; do
    [ -f "$f" ] || { echo "FAIL: no measurement screen at $f"; exit 1; }
done

grep -Fq "Weapon Hand  :mildly damaged holy keen glowing Sunb" "$inventory" || {
    echo "FAIL: inventory does not prove a Sunblade was wielded."
    echo "Screen: $inventory"
    exit 1
}
grep -Fq "Sunblade +2" "$activation" || {
    echo "FAIL: the activation menu does not prove the wielded Sunblade is known and +2."
    echo "Screen: $activation"
    exit 1
}
grep -Fq "Sunblade +2 (3 uses left)" "$activation" || {
    echo "FAIL: the Sunblade did not begin with its three daily light activations."
    echo "Screen: $activation"
    exit 1
}
grep -Fq "You squint and stagger in the bright light." "$activated" || {
    echo "FAIL: activating the Sunblade did not produce its bright light field."
    echo "Screen: $activated"
    exit 1
}
grep -Fq "Sunblade +2 (2 uses left)" "$activation_after" || {
    echo "FAIL: activating the Sunblade did not fire and spend one light-field use."
    echo "Screens: $activated and $activation_after"
    exit 1
}

resistance_number() {
    local value
    value="$(sed -nE "s/.*[[:space:]]$2[[:space:]]+(-?[0-9]+).*/\\1/p" "$1" | head -1)"
    echo "${value:-0}"
}

before_cold="$(resistance_number "$before" Cold)"
after_cold="$(resistance_number "$after" Cold)"
delta=$((after_cold - before_cold))
before_necr="$(resistance_number "$before" 'Life Drain')"
after_necr="$(resistance_number "$after" 'Life Drain')"
necr_delta=$((after_necr - before_necr))

echo "Sunblade plus: +2"
echo "Cold resistance without Sunblade: $before_cold"
echo "Cold resistance with Sunblade: $after_cold"
echo "Cold resistance delta: $delta"
echo "Life Drain resistance without Sunblade: $before_necr"
echo "Life Drain resistance with Sunblade: $after_necr"
echo "Life Drain resistance delta: $necr_delta"

if [ "$delta" -ne 2 ]; then
    echo "FAIL: a +2 Sunblade must add 2 Cold resistance at PLUS_1PER1."
    exit 1
fi
if [ "$necr_delta" -ne 4 ]; then
    echo "FAIL: a +2 Sunblade must retain its PLUS_2PER1 Life Drain resistance."
    exit 1
fi

echo "Light activation uses: 3 -> 2"
echo "PASS: the +2 Sunblade adds Cold 2 and Life Drain 4, and its light activation fires."
