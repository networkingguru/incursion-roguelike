#!/bin/bash
# Regression check for the rider attack that kept hitting a corpse, inc-upw.32.
#
# THE RULE. A natural attack written "A_BITE for 1d8 AD_PIERCE and AD_POIS
# (DC 16)" is one bite with a poison rider. Creature::Strike (src/Fight.cpp)
# throws EV_HIT for the bite and then walks the attack list throwing another
# EV_HIT for every "and" clause behind it. Nothing between those throws asked
# whether the victim had survived the first one, so a bite that killed was
# followed by a poison rider aimed at a corpse. esran reported that as a class
# of crash: handlers downstream of EV_HIT dereference the dead creature's map
# pointer.
#
# The fix stops a rider loop when its victim is dead, using isDead() -- the
# liveness test the rest of the engine already uses. It does NOT fix the
# handlers; that is the wider class, tracked as inc-wdi.
#
# THE SESSION. The player is turned into a giant spider and a hostile giant
# rat with 25 hit points stands east of him; both are arranged in the engine
# (Player::ChooseAction, under INCURSION_RIDER_PROBE) because the wizard
# menu's polymorph and summon prompts are interactive pickers no key script
# can drive. He bites until the rat dies. Seed 1, tools/keys/rider-corpse.keys.
#
# Measured 2026-08-22, same seed and script, src/Fight.cpp the only file
# different between the two builds:
#
#   before   2 riders thrown at a living rat, 1 rider thrown at the corpse,
#            1 EV_HIT delivered to the corpse
#   after    2 riders thrown at a living rat, 0 at the corpse, 0 EV_HIT
#            delivered to a corpse, and 1 rider loop recorded as stopped
#
# THE THIRD ASSERTION IS THE ONE THAT EARNS ITS KEEP. Riders must still go out
# while the victim lives. A fix that simply suppressed every rider would pass
# the first two assertions and quietly delete a monster's poison.
#
# A run that never reached the fight is INCONCLUSIVE, not FAIL. A dead session
# says nothing about the bug; sending somebody hunting a regression that a
# dead session invented is the mistake of inc-loa.3.
#
# Usage: tools/check_rider_corpse.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_RIDER_PROBE=1 tools/headless.sh tools/keys/rider-corpse.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
log="$run/logs/rider.log"

if echo "$out" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: the run never entered a map, so it measured nothing."
    echo "              Run dir: $run"
    exit 2
fi

[ -f "$log" ] || {
    echo "INCONCLUSIVE: the session wrote no probe log, so the scenario was"
    echo "              never arranged. Run dir: $run"
    exit 2
}

arranged=$(grep -c '^arranged:' "$log")
thrown_alive=$(grep -c 'rider-thrown .*(alive)' "$log")
thrown_dead=$(grep -c 'rider-thrown .*(dead)' "$log")
stopped=$(grep -c 'rider-stopped' "$log")
on_corpse=$(grep -c 'hit-on-corpse' "$log")

if [ "$arranged" -eq 0 ]; then
    echo "INCONCLUSIVE: the spider and the rat were never placed."
    echo "              Run dir: $run"
    exit 2
fi

if [ "$stopped" -eq 0 ] && [ "$thrown_dead" -eq 0 ] && [ "$on_corpse" -eq 0 ]; then
    echo "INCONCLUSIVE: the rat never died, so the session never reached the"
    echo "              state this check is about. Read $log"
    exit 2
fi

fail=0

if [ "$on_corpse" -gt 0 ]; then
    echo "FAIL: $on_corpse EV_HIT(s) were delivered to a creature already dead."
    echo "      That is inc-upw.32 back again. Lines:"
    grep 'hit-on-corpse' "$log" | sed 's/^/      /'
    fail=1
fi

if [ "$thrown_dead" -gt 0 ]; then
    echo "FAIL: $thrown_dead rider attack(s) were thrown at a dead victim."
    echo "      Creature::Strike's rider loop is not stopping. Lines:"
    grep 'rider-thrown .*(dead)' "$log" | sed 's/^/      /'
    fail=1
fi

if [ "$stopped" -eq 0 ]; then
    echo "FAIL: no rider loop reported stopping at a corpse, yet the rat died."
    echo "      The guard is not on the path this session takes. Read $log"
    fail=1
fi

if [ "$thrown_alive" -eq 0 ]; then
    echo "FAIL: not one rider was thrown at a living victim. The fix has taken"
    echo "      the poison away from every bite, not only from the killing one."
    echo "      Read $log"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: $thrown_alive rider(s) thrown at a living rat, $stopped rider"
    echo "      loop(s) stopped at the corpse, 0 blows landed on a corpse."
    echo "      Run dir: $run"
fi

exit "$fail"
