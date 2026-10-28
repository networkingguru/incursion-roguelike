#!/bin/bash
# gate: live
# Does an answered death prompt leave the screen when the player is engulfed?
# (bd inc-djbtl)
#
#   tools/check_stale_death_prompt.sh [seed ...]    default seeds: 1 2 3
#   exit 0 the prompt left the screen on every seed, 1 it stayed, 2 could not measure
#
# THE DEFECT. While the player is engulfed, TextTerm::ShowMap's engulfed branch
# never cleared UpdateMap and TextTerm::yn cleared the wrong window, so the
# "Die? [yn]" prompt stayed on screen after the player answered it. (src/Term.cpp)
#
# THE SESSION is tools/keys/engulf-stale-prompt.keys: a character summons a
# stunjelly beside him (the character is the frozen fixture), waits until "Engulfed" is on screen, waits until the game
# asks "Die? [yn]", answers n, and dumps the screen at each step.
#
# THE ORACLE is screen text in four dumps: engulfed holds "Engulfed", prompt
# holds "Die? [yn]", and answered holds no "Die? [yn]".
#
# fact: the death prompt appears -- tools/gates/Options.Dat (OPT_ELUDE_DEATH = 3)
# fact: the stunjelly stands beside the player -- wizard Monster Summoning, square chosen with RIGHT
# fact: the jelly engulfs (hit, then a failed Reflex save DC 15) -- key script loops "@until Engulfed ." bounded by SK_LOOP_MAX
# fact: the character dies while engulfed -- key script loops "@until Die? [yn] ." bounded by SK_LOOP_MAX
# fact: the character -- tools/fixtures/chars/low-dex-orc-barbarian-seed18-gate.sav, loaded with INCURSION_LOAD (DEX 7, Reflex -1)
# fact: the seed -- varies only combat rolls (a loaded save fixes the character); seeds 1 2 3 vary them, and the oracle reads screen text no roll changes
#
# IT CANNOT PASS BY DEFAULT. Exit 2 when a session did not play, a dump is
# missing, "Engulfed" never showed in the engulfed dump, or no live "Die? [yn]"
# showed in the prompt dump. Exit 1 only when the session is sound and an
# after-answer dump still shows "Die? [yn]".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }

OPTIONS=tools/gates/Options.Dat
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }
KEYS=tools/keys/engulf-stale-prompt.keys
FIXTURE=tools/fixtures/chars/low-dex-orc-barbarian-seed18-gate.sav
[ -f "$FIXTURE" ] || { echo "INCONCLUSIVE: fixture $FIXTURE is not there"; exit 2; }
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: $KEYS is not there"; exit 2; }

if [ "$#" -gt 0 ]; then SEEDS="$*"; else SEEDS="1 2 3"; fi
TOKEN="$$-$(date +%s)"
STALE=0; TOTAL=0

for seed in $SEEDS; do
    TOTAL=$((TOTAL+1))
    RUN="$ROOT/logs/runs/check-stale-death-prompt-$TOKEN-seed$seed"
    rm -rf "$RUN"
    out="$(INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTIONS" \
            INCURSION_LOAD="$FIXTURE" \
            tools/headless.sh "$KEYS" "$seed" 2>&1)"
    S="$RUN/logs/screens"
    if grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL|ASSERT' <<< "$out" \
       || ! grep -q 'ended: *cleanly' <<< "$out"; then
        echo "INCONCLUSIVE: seed $seed did not play to the end; see $RUN"
        exit 2
    fi
    for n in arrival summoned engulfed prompt answered; do
        [ -f "$(ls "$S"/*-$n.txt 2>/dev/null | head -1)" ] || {
            echo "INCONCLUSIVE: seed $seed left no '$n' screen dump; see $RUN"; exit 2; }
    done
    grep -q 'Hurk' "$(ls "$S"/*-arrival.txt | head -1)" || {
        echo "INCONCLUSIVE: seed $seed did not load the fixture character (no 'Hurk' on the arrival dump); see $RUN"; exit 2; }
    grep -q 'Engulfed' "$(ls "$S"/*-engulfed.txt | head -1)" || {
        echo "INCONCLUSIVE: seed $seed the engulfed dump does not show 'Engulfed'; see $RUN"; exit 2; }
    grep -qF 'Die? [yn]' "$(ls "$S"/*-prompt.txt | head -1)" || {
        echo "INCONCLUSIVE: seed $seed the prompt dump does not show 'Die? [yn]'; see $RUN"; exit 2; }
    if grep -qF 'Die? [yn]' "$(ls "$S"/*-answered.txt | head -1)"; then
        echo "seed $seed: STALE, 'Die? [yn]' is still on screen after the answer; see $RUN"
        STALE=$((STALE+1))
    else
        echo "seed $seed: ok, the prompt left the screen after the answer"
    fi
done

echo
if [ "$STALE" -gt 0 ]; then
    echo "FAIL: the answered death prompt stayed on screen on $STALE of $TOTAL seeds."
    exit 1
fi
echo "PASS: the answered death prompt left the screen on all $TOTAL seeds."
exit 0
