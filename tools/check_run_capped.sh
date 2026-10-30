#!/bin/bash
# gate: live
# Does tools/run_capped.py stop the WHOLE process group at its limit, so the
# game binary under headless.sh does not outlive the cut? (inc-xthfj)
#
# Starts a command that runs a 60 s grandchild `sleep`, caps it at 2 s, and
# requires exit 124 and a dead grandchild within 3 s. Also requires that a
# command finishing in time keeps its exit code, and that bad usage exits 2.
#
# fact: seed -- none; this check starts no game and reads no seed
# fact: timing -- fixed 2 s cap and 3 s grace on a `sleep`; no game load involved
# fact: run isolation -- own mktemp dir, removed on exit
#
# Usage: tools/check_run_capped.sh [--prove-red]
# --prove-red: run the same grandchild under the OLD method
# (perl alarm + exec) and require that the grandchild SURVIVES, printing
# PROVED RED. This shows the check can see the defect.
# Exit 0 pass (or proved red), 1 fail, 2 could not be judged.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RED=0
case "${1:-}" in
  "") ;;
  --prove-red) RED=1 ;;
  *) echo "usage: $0 [--prove-red]" >&2; exit 2 ;;
esac
TMP=$(mktemp -d) || exit 2
PIDF="$TMP/pid"
cleanup() {
  [ -s "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT
CHILD='sleep 60 & echo $! > "$1"; wait'

alive() { kill -0 "$1" 2>/dev/null; }
gone_within() { # pid seconds
  local i
  for i in $(seq 1 $(($2 * 10))); do alive "$1" || return 0; sleep 0.1; done
  return 1
}

if [ $RED = 1 ]; then
  perl -e 'alarm 2; exec @ARGV' bash -c "$CHILD" _ "$PIDF" >/dev/null 2>&1
  [ -s "$PIDF" ] || { echo "no grandchild pid recorded"; exit 2; }
  gpid=$(cat "$PIDF")
  sleep 1
  if alive "$gpid"; then echo "old method left grandchild $gpid running"; echo "PROVED RED"; exit 0; fi
  echo "NOT RED: old method also killed the grandchild"; exit 1
fi

tools/run_capped.py 2 bash -c "$CHILD" _ "$PIDF" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 124 ] || { echo "FAIL: cut run exited $rc, expected 124"; exit 1; }
[ -s "$PIDF" ] || { echo "no grandchild pid recorded"; exit 2; }
gpid=$(cat "$PIDF")
gone_within "$gpid" 3 || { echo "FAIL: grandchild $gpid survived the cut"; exit 1; }

tools/run_capped.py 5 bash -c 'exit 3' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] || { echo "FAIL: in-time exit code $rc, expected 3"; exit 1; }
tools/run_capped.py 5 true >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: in-time exit code $rc, expected 0"; exit 1; }
tools/run_capped.py >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: no-args exit $rc, expected 2"; exit 1; }
tools/run_capped.py abc true >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: bad SECONDS exit $rc, expected 2"; exit 1; }
tools/run_capped.py 0 true >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: zero SECONDS exit $rc, expected 2"; exit 1; }

# A leader like headless.sh, with several children that exit the moment TERM
# arrives. Darwin may answer the final SIGKILL to the group with EPERM (only
# zombies left); the tool must still exit 124. Measured on the unfixed tool:
# about 1 run in 3 failed, so 30 runs see it almost surely.
LEADER='for k in 1 2 3 4 5 6; do bash -c "trap \"exit 0\" TERM; while :; do sleep 0.1; done" & done; wait'
n=0
while [ "$n" -lt 30 ]; do
  n=$((n+1))
  err=$(tools/run_capped.py 0.3 bash -c "$LEADER" 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 124 ] || { echo "FAIL: headless-shaped run $n exited $rc, expected 124"; exit 1; }
  case "$err" in *Traceback*) echo "FAIL: headless-shaped run $n printed a traceback"; exit 1 ;; esac
done
echo "PASS"
