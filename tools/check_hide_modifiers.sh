#!/bin/bash
# gate: live
# inc-u3dp phase 1, part 3: the pure hide-check modifier functions match the
# rules. (0 GREEN, 1 RED, 2 INCONCLUSIVE)
#
# THE ORACLE is INCURSION_HIDE_MOD_PROBE, which arms HideModProbe
# (src/HideModProbe.cpp) at the top of Game::Play. It drives SpotModifiers'
# light path through HideSpotModifiersForTest (exact light levels), ListenModifiers,
# HiderModifiers and ItemSizePenalty, printing one line per case:
#   HIDE_MOD case=<name> expect=<n> got=<n>
# The expected values are the literal numbers from the rules; the probe never
# computes an expected value with the functions under test.
#
# GREEN: every case has expect == got, and there are exactly HM_CASES case
# lines. RED: a mismatch, or the wrong number of case lines. The comparison is
# hard-coded here, not in the probe, so a probe that mis-counts fails.
#
# Usage: tools/check_hide_modifiers.sh [seed]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SEED="${1:-1}"
OPTS="tools/fixtures/options-2026-08-22.dat"
HM_CASES=41

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
RUN="logs/hide-modifiers-$$"
rm -rf "$RUN"
INCURSION_HIDE_MOD_PROBE=1 INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTS" \
    tools/headless.sh tools/keys/hide-no-spot-roll.keys "$SEED" > "$RUN.out" 2>&1
LOG="$RUN/logs/errors.log"
[ -f "$LOG" ] || { echo "INCONCLUSIVE: no errors.log; see $RUN.out"; exit 2; }
grep -v '^    ' "$LOG" | grep 'HIDE_MOD' > "$RUN.lines"

grep -q 'HIDE_MOD INCONCLUSIVE' "$RUN.lines" && {
    echo "INCONCLUSIVE: $(grep -m1 'HIDE_MOD INCONCLUSIVE' "$RUN.lines")"; exit 2; }
grep -q 'HIDE_MOD COMPLETE' "$RUN.lines" || {
    echo "INCONCLUSIVE: probe did not complete ($RUN.lines)"; exit 2; }

n="$(grep -c 'HIDE_MOD case=' "$RUN.lines")"
if [ "$n" -ne "$HM_CASES" ]; then
    echo "RED: probe emitted $n cases, expected $HM_CASES. Run: $RUN"
    exit 1
fi

bad="$(grep 'HIDE_MOD case=' "$RUN.lines" | \
    sed -n 's/.*case=\([^ ]*\) expect=\(-\{0,1\}[0-9]*\) got=\(-\{0,1\}[0-9]*\).*/\1 \2 \3/p' | \
    awk '$2 != $3 { print "  " $1 " expect=" $2 " got=" $3 }')"
if [ -n "$bad" ]; then
    echo "RED: modifier verdicts disagree with the rules:"
    echo "$bad"
    echo "Run: $RUN"
    exit 1
fi
echo "GREEN: all $n hide-modifier cases match the rules. Run: $RUN"
exit 0
