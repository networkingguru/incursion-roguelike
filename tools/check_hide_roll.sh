#!/bin/bash
# gate: live
# inc-u3dp phase 2a-1: the opposed hide/spot check, the stored HK_SPOT_RESULT
# verdict and the trigger loop match the rules. (0 GREEN, 1 RED, 2 INCONCLUSIVE)
#
# THE ORACLE is INCURSION_HIDE_ROLL_PROBE, which arms HideRollProbe
# (src/HideRollProbe.cpp) at the top of Game::Play. It drives SpotCheck,
# IsSpotted, HideCanWatch and HideTrigger and prints one line per case:
#   HIDE_ROLL case=<name> expect=<n> got=<n>
# The expected values are the literal truth values from the rules; the probe
# never computes an expected value with the functions under test.
#
# GREEN: every case has expect == got, and there are exactly HR_CASES case
# lines. RED: a mismatch, or the wrong number of case lines. The comparison is
# hard-coded here, not in the probe, so a probe that mis-counts fails.
#
# Usage: tools/check_hide_roll.sh [seed]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SEED="${1:-1}"
OPTS="tools/fixtures/options-2026-08-22.dat"
HR_CASES=15

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
RUN="logs/hide-roll-$$"
rm -rf "$RUN"
INCURSION_HIDE_ROLL_PROBE=1 INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTS" \
    tools/headless.sh tools/keys/hide-no-spot-roll.keys "$SEED" > "$RUN.out" 2>&1
LOG="$RUN/logs/errors.log"
[ -f "$LOG" ] || { echo "INCONCLUSIVE: no errors.log; see $RUN.out"; exit 2; }
grep -v '^    ' "$LOG" | grep 'HIDE_ROLL' > "$RUN.lines"

grep -q 'HIDE_ROLL INCONCLUSIVE' "$RUN.lines" && {
    echo "INCONCLUSIVE: $(grep -m1 'HIDE_ROLL INCONCLUSIVE' "$RUN.lines")"; exit 2; }
grep -q 'HIDE_ROLL COMPLETE' "$RUN.lines" || {
    echo "INCONCLUSIVE: probe did not complete ($RUN.lines)"; exit 2; }

n="$(grep -c 'HIDE_ROLL case=' "$RUN.lines")"
if [ "$n" -ne "$HR_CASES" ]; then
    echo "RED: probe emitted $n cases, expected $HR_CASES. Run: $RUN"
    exit 1
fi

bad="$(grep 'HIDE_ROLL case=' "$RUN.lines" | \
    sed -n 's/.*case=\([^ ]*\) expect=\(-\{0,1\}[0-9]*\) got=\(-\{0,1\}[0-9]*\).*/\1 \2 \3/p' | \
    awk '$2 != $3 { print "  " $1 " expect=" $2 " got=" $3 }')"
if [ -n "$bad" ]; then
    echo "RED: check verdicts disagree with the rules:"
    echo "$bad"
    echo "Run: $RUN"
    exit 1
fi
echo "GREEN: all $n hide-roll cases match the rules. Run: $RUN"
exit 0
