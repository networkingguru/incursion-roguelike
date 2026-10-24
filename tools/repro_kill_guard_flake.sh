#!/bin/bash
# Reproduce the check_kill_guard.sh "an outside process could not be killed"
# flake under CPU load (bead inc-qi0g).
#
#   tools/repro_kill_guard_flake.sh [runs=20] [parallel=4] [load-multiplier=2]
#
# Starts hw.ncpu * multiplier `yes` load processes, runs the check `runs` times
# in batches of `parallel`, counts runs whose output holds the FAIL line, and
# kills every load process it started on exit.
# Exit: 0 no false failure, 1 at least one, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNS="${1:-20}"
PAR="${2:-4}"
MULT="${3:-2}"
OUT="$ROOT/logs/repro-kill-guard-flake"
LOAD_PIDS=""

cleanup() {
    for p in $LOAD_PIDS; do kill "$p" 2>/dev/null; done
}
trap cleanup EXIT

until "$ROOT/tools/load_guard.sh" >/dev/null 2>&1; do sleep 30; done

mkdir -p "$OUT"
rm -f "$OUT"/run-*.txt

N=$(( $(sysctl -n hw.ncpu) * MULT ))
for _ in $(seq 1 "$N"); do
    yes >/dev/null &
    LOAD_PIDS="$LOAD_PIDS $!"
done

i=0
while [ "$i" -lt "$RUNS" ]; do
    batch=0
    CHK_PIDS=""
    while [ "$batch" -lt "$PAR" ] && [ "$i" -lt "$RUNS" ]; do
        i=$((i + 1)); batch=$((batch + 1))
        "$ROOT/tools/check_kill_guard.sh" >"$OUT/run-$i.txt" 2>&1 &
        CHK_PIDS="$CHK_PIDS $!"
    done
    wait $CHK_PIDS
done

BAD=$(grep -l "could not be killed" "$OUT"/run-*.txt 2>/dev/null | wc -l | tr -d ' ')
OTHER=$(grep -L "^PASS: check_kill_guard.sh" "$OUT"/run-*.txt 2>/dev/null | wc -l | tr -d ' ')
echo "runs=$RUNS parallel=$PAR load_procs=$N could_not_be_killed=$BAD not_passing=$OTHER specimens=$OUT"
[ "$BAD" -eq 0 ]
