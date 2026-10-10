#!/bin/bash
# gate: live
# inc-u3dp: real Monster::ChooseAction hooks, 60 still actions and 60 LOS cycles.
# Placement changes the scene; only ChooseAction may create/clear results.
# Removing its hook leaves missing rolls; unconditional rerolls fail still.
# Usage: tools/check_hide_no_spot_roll.sh [seed]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SEED="${1:-1}"
OPTS="tools/fixtures/options-2026-08-22.dat"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
RUN="logs/hide-no-spot-roll-$$"
rm -rf "$RUN"
INCURSION_HIDE_PROBE=1 INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTS" \
    tools/headless.sh tools/keys/hide-no-spot-roll.keys "$SEED" > "$RUN.out" 2>&1
LOG="$RUN/logs/errors.log"
[ -f "$LOG" ] || { echo "INCONCLUSIVE: no errors.log; see $RUN.out"; exit 2; }
grep -v '^    ' "$LOG" | grep 'HIDE_PROBE' > "$RUN.lines"

grep -q 'HIDE_PROBE INCONCLUSIVE' "$RUN.lines" && {
    echo "INCONCLUSIVE: $(grep -m1 'HIDE_PROBE INCONCLUSIVE' "$RUN.lines")"; exit 2; }
grep -q 'HIDE_PROBE COMPLETE' "$RUN.lines" || { echo "INCONCLUSIVE: probe did not complete ($RUN.lines)"; exit 2; }
grep -q 'setup .*hostile=1 control_unhidden=1' "$RUN.lines" || {
    echo "INCONCLUSIVE: rat is not hostile, or does not see the unhidden player ($RUN.lines)"; exit 2; }
echo "setup: $(grep -m1 'HIDE_PROBE setup' "$RUN.lines" | sed 's/.*HIDE_PROBE setup //')"

python3 - "$RUN.lines" <<'ORACLE'
import re
import sys
text = open(sys.argv[1]).read()
rows = re.findall(r'phase=(still|away|moves) round=(\d+) current=([01]) spotted=([01]) perceived=([01])', text)
phases = {p: [r for r in rows if r[0] == p] for p in ('still', 'away', 'moves')}
for phase, records in phases.items():
    if len(records) != 60 or [int(r[1]) for r in records] != list(range(60)):
        print(f'INCONCLUSIVE: {phase} has {len(records)} actions/cycles, want 60 in order')
        sys.exit(2)
    print(f'{phase}: 60 actions; perceived 0={sum(r[4] == "0" for r in records)} 1={sum(r[4] == "1" for r in records)}')
if any(r[2] != '1' for p in ('still', 'moves') for r in phases[p]):
    print('RED: missing rolls from Monster::ChooseAction HideTurnStart hook')
    sys.exit(1)
if any(r[2] != '0' for r in phases['away']):
    print('RED: loss of sight did not clear the stored result')
    sys.exit(1)
if any(r[3] != r[4] for p in ('still', 'moves') for r in phases[p]):
    print('RED: perception disagrees with stored result')
    sys.exit(1)
if len({r[4] for r in phases['still']}) != 1:
    print('RED: still phase re-rolled without a situation change')
    sys.exit(1)
if len({r[4] for r in phases['moves']}) != 2:
    print('RED: missing fresh rolls on regained sight; tied pair gave one answer')
    sys.exit(1)
print('GREEN: still result stable for 60 actions; both answers across 60 LOS cycles')
ORACLE
result=$?
echo "Run: $RUN"
exit "$result"
