#!/bin/bash
# gate: live
# Regression check for inc-83dw: a trip must not make the tripper attack himself.
#
# THE DEFECT. src/Fight.cpp, case AD_TRIP of Creature::Damage, called
# e.EActor->ProvokeAoO(e.EActor). Creature::ProvokeAoO(c) builds its event with
# c as the ATTACKER and this as the VICTIM, so passing the same pointer twice
# made the tripper both. A successful trip armed the tripper's own weapon and
# swung it at him, brand and all. src/Message.cpp drops the actor clause when
# actor equals victim, so the player never read who had hit him. The counter-
# trip path swaps actor and victim and re-enters the same code, so a monster
# that won a counter-trip attacked itself too.
#
# The argument is now e.EVictim: the tripped foe delivers the attack. That is
# what the game's own Trip entry tells the player -- "you provoke an attack of
# opportunity when you attempt to trip a foe" (src/Player.cpp) -- and what
# Master Trip exempts him from.
#
# WHAT THE PROBE RECORDS. INCURSION_TRIP_AOO_PROBE=1 writes one line per attack
# of opportunity Creature::OAttack accepts, naming its actor, its victim and
# whether they are one creature. The failing signature is the whole of
#
#     self=1
#
# and it does not matter which creature it names: the player hitting himself and
# a goblin hitting itself are the same defect on the two sides of the counter.
#
# WHY THE CHECK ALSO DEMANDS A GOBLIN ATTACKING THE PLAYER. Deleting the
# ProvokeAoO call would drive self=1 to zero as surely as fixing the argument,
# and would silently remove a rule the game documents. So the run must show the
# tripped foe answering: actor=<goblin> victim=<Holg>. Both columns are read for
# that reason.
#
# Measured 2026-09-16, seed 5, tools/fixtures/options-2026-08-22.dat, two
# binaries differing only by -DINCURSION_TRIP_AOO_UNFIXED. Three attacks of
# opportunity on each build, at the same three turns:
#
#   unfixed  self=1 x3   actor=<Holg> victim=<Holg> twice,
#                        actor=<goblin> victim=<goblin> once (the counter-trip
#                        mirror case, which nobody had reported); the player's
#                        hit points fall to 34/36 by his own hand.
#   fixed    self=0 x3   actor=<goblin> victim=<Holg> twice,
#                        actor=<Holg> victim=<goblin> once (the counter-trip,
#                        now delivered by the creature that was tripped).
#
# The COUNT and the TURNS are identical on both builds, which is the control:
# the fix redirects the attack and does not remove it.
#
# HOW TO PROVE THIS RED AGAIN. There is no --prove-red switch, because the red
# side is a whole build rather than one mutated line:
#
#   BACKEND=posix EXTRA_CXXFLAGS=-DINCURSION_TRIP_AOO_UNFIXED \
#       OUT=incursion-trip-unfixed ./build_macos.sh
#   INCURSION_BIN=./incursion-trip-unfixed tools/check_trip_aoo.sh   # exit 1
#
# INCURSION_BIN is read by tools/headless.sh, so the swap needs no other change.
# Delete incursion-trip-unfixed afterwards; it is not a shipped binary.
#
# Exit: 0 no attack of opportunity hit its own actor, and the foe answered
#       1 the defect is present
#       2 the run measured nothing, so it says nothing about the fix
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

SEED="${SEED:-5}"
export INCURSION_OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"
export INCURSION_TRIP_AOO_PROBE=1

out="$(tools/headless.sh tools/keys/trip-aoo.keys "$SEED" 2>&1)"
status=$?
run="$(echo "$out" | awk '/^run:/ {print $2}')"
log="$run/logs/tripaoo.log"

# HOW THE SESSION ENDED IS PART OF THE MEASUREMENT. tools/headless.sh exits 0
# for a clean finish and 3 when the key script runs out. Every other code says
# the session stopped being a game, and a probe log written before a crash is
# not evidence about the fix. See inc-mpw8.
if [ "$status" -ne 0 ] && [ "$status" -ne 3 ]; then
    echo "INCONCLUSIVE: the session ended badly (tools/headless.sh exit $status),"
    echo "              so nothing after that point is gameplay and the probe"
    echo "              log is not evidence about the fix."
    echo "$out" | sed -n '/^--- after the session ---/,$p' | sed 's/^/  /'
    exit 2
fi

# The control: a trip must have LANDED. A failed trip never reaches
# Creature::Damage, so a run that won no opposed check says nothing at all.
landed="$(grep -lh "you trip a goblin" "$run"/logs/screens/*.txt 2>/dev/null | wc -l | tr -d ' ')"
if [ "${landed:-0}" -lt 1 ]; then
    echo "INCONCLUSIVE: no trip landed in this session, so Creature::Damage never"
    echo "              reached case AD_TRIP and no attack of opportunity was due."
    echo "              Run dir: ${run:-unknown}"
    exit 2
fi

if [ -z "$run" ] || [ ! -f "$log" ]; then
    echo "INCONCLUSIVE: a trip landed but the session wrote no probe log, so no"
    echo "              attack of opportunity was accepted at all. Every target"
    echo "              may have held a spent counter."
    echo "              Run dir: ${run:-unknown}"
    exit 2
fi

total="$(grep -c 'oattack ' "$log")"
self="$(grep -c 'self=1' "$log")"

if [ "$self" -gt 0 ]; then
    echo "FAIL: $self of $total attack(s) of opportunity hit their own actor."
    grep 'self=1' "$log" | sed 's/^/    | /'
    echo "Run dir: $run"
    exit 1
fi

# A fix that deleted the call would also show zero self-attacks. The tripped
# foe must be seen answering the trip.
answered="$(grep -c 'actor=<goblin> victim=<Holg>' "$log")"
if [ "$answered" -lt 1 ]; then
    echo "INCONCLUSIVE: no self-attack, but no goblin answered a trip either, so"
    echo "              this run cannot tell a corrected argument from a deleted"
    echo "              call. Run dir: $run"
    exit 2
fi

echo "PASS: no attack of opportunity hit its own actor."
echo "      $total accepted; $answered delivered by the tripped goblin."
exit 0
