#!/bin/bash
# gate: live
# Does deep water honour WATER_BREATHING? bd inc-jkyf.
#
# THE DEFECT. The status WATER_BREATHING (inc/Defines.h) is read nowhere.
# Deep water (lib/dungeon.irh, EV_MOVE and EV_MON_CONSIDER) exempts amphibians,
# aquatic, water, incorporeal, non-breathing, water-walking and aerial
# creatures from the Swim check, drowning and the warning prompt, and never
# tests WATER_BREATHING. Ruling: a creature (or mount) with WATER_BREATHING is
# treated exactly like an amphibian.
#
# THE SESSION. tools/keys/water-breathing-deep-water.keys wears the Ring of
# Elemental Command (Water), which grants WATER_BREATHING, puts one deep water
# square east of the player and steps into it.
#
# THE ORACLE, read from the screen dumps:
#   - the prompt "Confirm enter the deep water?" after the step  -> FAIL
#   - "You fail to make progress" / "You are drowning!" / the
#     "Swimming Check" line on a later screen                    -> FAIL
#   - the player stands one square east, past the old square     -> required
# Inconclusive (exit 2): no build, the ring never reached a finger, no deep
# water east of the player, no gameplay, or the player never entered the square.
#
# Usage: tools/check_water_breathing.sh     (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

mkdir -p logs
rundir="logs/runs/water-breathing-$$"
out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat INCURSION_RUN_DIR="$rundir" \
    tools/headless.sh tools/keys/water-breathing-deep-water.keys 1 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
[ -n "$run" ] || run="$rundir"
if grep -q "the key script looked for something" <<< "$out"; then
    echo "INCONCLUSIVE: the key script could not find something on screen. Run: $run"
    exit 2
fi
if grep -q "STALLED" <<< "$out"; then
    echo "INCONCLUSIVE: the session spent no game time, so nothing was measured. Run: $run"
    exit 2
fi

scr="$run/logs/screens"
ring="$scr/0001-ring-on.txt"
pool="$scr/0002-pool.txt"
prompt="$scr/0003-prompt.txt"
entered="$scr/0004-entered.txt"
steps="$scr/0005-steps.txt"
for f in "$ring" "$pool" "$prompt" "$entered" "$steps"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: no screen dumped at $f"; exit 2; }
done

grep -q "Left Ring    :Ring of Elemental Command (Water)" "$ring" || {
    echo "INCONCLUSIVE: the water ring never reached a finger, so the character"
    echo "              holds no WATER_BREATHING. Screen: $ring"
    exit 2
}
grep -q "@~" "$pool" || {
    echo "INCONCLUSIVE: no deep water square east of the player. Screen: $pool"
    exit 2
}

rc=0
if grep -q "Confirm enter the deep water" "$prompt"; then
    echo "FAIL: deep water warns a WATER_BREATHING character. Screen: $prompt"
    grep "Confirm enter the deep water" "$prompt" | cut -c1-66
    rc=1
fi
for f in "$entered" "$steps"; do
    if grep -qE "You fail to make progress|You are drowning|Swimming Check" "$f"; then
        echo "FAIL: deep water made a WATER_BREATHING character swim. Screen: $f"
        grep -E "You fail to make progress|You are drowning|Swimming Check" "$f" | cut -c1-66
        rc=1
    fi
done
if [ "$rc" = 0 ]; then
    grep -q "<@" "$entered" || {
        echo "INCONCLUSIVE: the player never stepped onto the deep water square. Screen: $entered"
        exit 2
    }
    echo "  ok: deep water treats a WATER_BREATHING character like an amphibian"
fi
exit $rc
