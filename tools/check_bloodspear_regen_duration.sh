#!/bin/bash
# Behavioral check for F41 / inc-tek.8.8: a Bloodspear critical grants the orc
# wielder regeneration whose INITIAL duration is amt*20 turns, not amt*5.
#
# THE ORACLE is the REGEN stati's "[Dur N]" line in the wizard "Examine Player
# Data" dump (src/Debug.cpp:1590), the only place the regeneration's remaining
# turns reach a screen. tools/keys/bloodspear-regen-duration.keys forces the
# critical with a Coup de Grace on a sleeping goblin. At seed 4 the fixed build
# reads [Dur 899]; the pre-fix amt*5 build reads [Dur 224] (see
# tools/oracle_ab.sh 36bf101 ... seed 4). This check requires a REGEN [Dur N]
# with N well above the pre-fix value, so the amt*20 path is what ran.
#
# The structural companion tools/check_bloodspear_regen.sh guards all four
# duration multipliers in the source; this check proves the initial-crit path
# behaves.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=4
KEYS=tools/keys/bloodspear-regen-duration.keys
MIN_DUR=450   # midpoint of the pre-fix 224 and the fixed 899; amt*5 falls below

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

sleep_screen="$run/logs/screens/0002-after-sleep.txt"
coup_screen="$run/logs/screens/0003-after-coup.txt"
dump_screen="$run/logs/screens/0004-player-dump.txt"
for f in "$sleep_screen" "$coup_screen" "$dump_screen"; do
    [ -f "$f" ] || { echo "FAIL: no measurement screen at $f"; exit 1; }
done

grep -Fq "collapses into slumber" "$sleep_screen" || {
    echo "FAIL: the Scroll of Sleep did not put the goblin to sleep; no helpless"
    echo "       target means no Coup de Grace and no critical."
    echo "Screen: $sleep_screen"
    exit 1
}
grep -Eq "killing blow|blood quicken" "$coup_screen" || {
    echo "FAIL: the Coup de Grace did not land a critical that started the regen."
    echo "Screen: $coup_screen"
    exit 1
}

dur="$(grep -oE "REGEN from SS ENCH .*\[Dur [0-9]+\]" "$dump_screen" | grep -oE "[0-9]+\]" | tr -d ']' | head -1)"
if [ -z "$dur" ]; then
    echo "FAIL: no REGEN [Dur N] line in the player dump; the regen never started."
    echo "Screen: $dump_screen"
    exit 1
fi

echo "Bloodspear regen initial duration ([Dur N]): $dur"
if [ "$dur" -lt "$MIN_DUR" ]; then
    echo "FAIL: [Dur $dur] is below $MIN_DUR -- the pre-fix amt*5 duration, not amt*20."
    exit 1
fi

echo "PASS: F41 / inc-tek.8.8 grants the Bloodspear's initial-crit regen at amt*20 turns."
