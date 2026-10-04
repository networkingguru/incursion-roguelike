#!/bin/bash
# gate: live
#
# Regression check for the avoid-chance shown on the known-trap prompt
# (inc-o6xj): the number Creature::SaveChance reports to the player and the
# outcome Creature::SavingThrow decides must come from one rule, not two.
#
# THE ORACLE is logs/errors.log, written by SaveChanceProbe (src/Fight.cpp)
# under INCURSION_SAVECHANCE_PROBE. For each save type (FORT, REF, WILL), each
# DC in {0,5,10,15,20,25,30,40} and each subtype the trap path uses
# (0, SA_TRAPS, SA_TRAPS|SA_MAGIC), the probe reads SaveChance's own number,
# then forces every d20 result 1..20 through the real SavingThrow (via
# LOFSetForcedSaveThrowRoll) and counts successes. SaveChance must equal
# hits*5; the probe writes one "SAVECHANCE ..." line per case and a final
# "SAVECHANCE_DONE mismatches=M".
#
# The check demands mismatches=0 and at least 72 SAVECHANCE case lines
# (3 types x 8 DCs x 3 subtypes), and fails when the probe wrote nothing.
#
# Usage: tools/check_save_chance.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/save-chance.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(INCURSION_SAVECHANCE_PROBE=1 INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

log="$run/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. The probe never wrote anything -- is"
    echo "      SaveChanceProbe still called from Game::Play()?"
    exit 1
fi

lines="$(grep 'SAVECHANCE' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no SAVECHANCE lines."
    exit 1
fi

if grep -q 'INCONCLUSIVE' <<< "$lines"; then
    echo "FAIL: the probe could not run:"
    echo "$lines" | grep 'INCONCLUSIVE'
    exit 1
fi

done_line="$(echo "$lines" | grep 'SAVECHANCE_DONE ')"
if [ -z "$done_line" ]; then
    echo "FAIL: no SAVECHANCE_DONE line -- the probe did not finish."
    echo "$lines"
    exit 1
fi

cases="$(echo "$lines" | grep -c '^.*SAVECHANCE type=')"
mismatches="$(echo "$done_line" | sed -n 's/.*mismatches=\([0-9]*\).*/\1/p')"

echo "$lines"
echo

if [ "$cases" -lt 72 ]; then
    echo "FAIL: only $cases SAVECHANCE case lines (want >=72)"
    exit 1
fi

if [ "$mismatches" != "0" ]; then
    echo "FAIL: $done_line (want mismatches=0)"
    exit 1
fi

echo "PASS: $done_line (cases=$cases)"
