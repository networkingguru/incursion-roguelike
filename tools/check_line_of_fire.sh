#!/bin/bash
# gate: live
#
# Regression check for the saving-throw cover-and-band rule (inc-30ps
# rework): each occupied square between shooter and target gives a weapon
# attack a -4 penalty, the target's own square gives a further -4 if the
# target is not its head, the shot rolls once, and a miss is resolved by
# BAND -- the band names a SQUARE, and every creature in it, in contents-
# chain order, makes a Reflex save at DC 10+(total-D) until one fails; that
# creature is struck, or the shot misses if all save. See "The rule" in
# docs/specs/2026-09-21-line-of-fire-spec.md.
#
# THE ORACLE is logs/errors.log, written by LineOfFireProbe (src/Fight.cpp)
# under INCURSION_LOF_PROBE. The probe places five rats in a line -- "near"
# (distance 2), "far" (distance 3), and "cover"/"target"/"extra" sharing the
# square at distance 4 in that contents-chain order -- pins the target's
# Defense Class relative to the shooter's own calibrated to-hit bonus (so
# every case's forced roll stays inside 1-20), and throws a dagger at it
# once per case under a forced d20 roll (LOFForcedRoll, src/Fight.cpp) and,
# where a save matters, a forced save outcome (LOFSetForcedSave), reading
# back which rat lost hit points (or MULTIPLE, if more than one did).
#
# Cases: both boundaries of each of the three bands, a natural 20, a roll
# below the bare Defense Class, one Precise Shot case; the save walk
# reaching the second and third creature of a square and a whole-square
# save (miss); the save DC logged at two different bands; a displaced
# target producing a clean miss whether the roll is in band range, at the
# would-auto-hit boundary, or (this one pre-existing, not a defect) bypassed
# by a literal natural 20; two Flawless Dodge cases -- ruled 2026-09-22, a
# natural 20 always hits and Flawless Dodge cannot stop one, so
# flawless-dodge-nat20 asserts the TARGET is hit even under heavy cover,
# while flawless-dodge-ordinary-hit asserts an arithmetic (non-20) hit is
# still a clean miss that leaves the whole line alone, the original point
# of job 2 (see both cases' comments in LineOfFireProbe); a struck
# bystander's damage using its own size, not the target's; and five more
# cases for "A shot with no chosen creature" (same spec) fired at an empty
# square with ThrowXY -- far, cover, target and extra taken off the map so
# only "near" is on the line for the lone-creature boundary (no penalty,
# both sides), then far restored with cover/target/extra still off so their
# square is the empty aim point, exercising "hits the first square", "fails
# the first, hits the second" and "fails every square" under the flat -4;
# and two more (inc-55jl) that force a killing hit -- a natural 20 against
# a target with cHP=1 -- and confirm the dagger lands on the victim's own
# former square rather than (1,1) (PlaceAt's crash-guard fallback), once
# through the Intended branch and once through the no-Intended branch.
#
# Amendment 1 (inc-55jl, the rest of the 11a8f7b defects): dead-before-
# strike (a stale reference to an already-dead/off-map Intended, built like
# Throw() itself since Throw() carries no X/Y, is not struck and lands at
# the square its EXVal/EYVal name); target-behind-wall (a "Dungeon Wall"
# terrain square between shooter and target stops the flight, so a forced
# nat 20 still strikes nothing and lands on the last clear square);
# clean-miss-lands-on-target (a forced miss with no band lands on the
# target's own square -- read from LOFGetLastLandX/Y, the pre-placement
# decision, since Thing::PlaceNear will not rest an item on the live
# target's own square and always nudges it one tile off); and
# returning-no-band (WQ_RETURNING skips the band entirely, so a roll that
# would otherwise redirect onto a bystander is a clean miss).
#
# Each case writes one "LOF_PROBE: case=... PASS|FAIL" line, and a final
# "LOF_PROBE: RESULT pass=N fail=N" line.
#
# Usage: tools/check_line_of_fire.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/line-of-fire.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(INCURSION_LOF_PROBE=1 INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

log="$run/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. The probe never wrote anything -- is"
    echo "      LineOfFireProbe still called from Game::Play()?"
    exit 1
fi

# errors.log timestamps every line and prints a one-time call stack after a
# message's first occurrence (tools/headless.sh convention), so match the
# marker as a substring, not an anchor.
lines="$(grep 'LOF_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no LOF_PROBE lines."
    exit 1
fi

if grep -q 'INCONCLUSIVE' <<< "$lines"; then
    echo "FAIL: the probe could not run its scenario:"
    echo "$lines" | grep 'INCONCLUSIVE'
    exit 1
fi

result="$(echo "$lines" | grep 'LOF_PROBE: RESULT ')"
if [ -z "$result" ]; then
    echo "FAIL: no LOF_PROBE: RESULT line -- the probe did not finish."
    echo "$lines"
    exit 1
fi

echo "$lines"
echo

pass="$(echo "$result" | sed -n 's/.*pass=\([0-9]*\).*/\1/p')"
fail="$(echo "$result" | sed -n 's/.*fail=\([0-9]*\).*/\1/p')"

if [ -z "$pass" ] || [ -z "$fail" ]; then
    echo "FAIL: could not parse '$result'"
    exit 1
fi

if [ "$fail" != "0" ] || [ "$pass" -lt 35 ]; then
    echo "FAIL: $result (want fail=0 and pass>=35)"
    exit 1
fi

echo "PASS: $result"
