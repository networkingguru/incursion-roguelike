#!/bin/bash
# gate: live
# Does a monster that reuses a stored route only step along a route it stands
# on, onto a square that passes RunOver? (inc-vhkei)
#
# A build with -DREUSE_SELFCHECK recomputes, on every reuse in
# Monster::SmartDirTo, whether the monster stands on the stored route and
# whether RunOver accepts the returned square (bad counts each failure), and
# reruns a fresh ShortestPath (unreachable counts a target the fresh search
# cannot reach; reported, not failed, because a stored route can be blocked
# further along and the monster re-searches there). It prints
# REUSE_SELFCHECK reuses=<n> bad=<m> unreachable=<k> every 1000 reuses and at
# exit. This check runs dive.keys on seeds 1 3 6 8 16 and FAILS unless every
# run printed the line, total reuses exceed 1000 and bad is 0.
#
# fact: which routes are reused -- none; the self-check judges every reuse, whatever the seed plays
# fact: settings -- tools/gates/Options.Dat
# fact: run isolation -- unique INCURSION_RUN_DIR per run
# fact: how long a seed runs -- 60 s is a per-seed sampling budget (the summary line prints every
#   1000 calls, so a cut run still counts); tools/run_capped.py enforces it on the whole process
#   group, and a hang is bounded by the same limit
#
# Usage: tools/check_route_reuse.sh [--no-build] [--prove-red]
# --prove-red: build with -DREUSE_BREAK (the next-square RunOver test is
# skipped) and require bad > 0, printing PROVED RED.
# Exit 0 pass (or proved red), 1 fail, 2 could not be judged.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD=1; RED=0
for a in "$@"; do
  case "$a" in
    --no-build) BUILD=0 ;;
    --prove-red) RED=1 ;;
    *) echo "usage: $0 [--no-build] [--prove-red]" >&2; exit 2 ;;
  esac
done
OUT=incursion-reuse-check; FLAGS=-DREUSE_SELFCHECK
if [ $RED = 1 ]; then OUT=incursion-reuse-red; FLAGS="-DREUSE_SELFCHECK -DREUSE_BREAK"; fi
if [ $BUILD = 1 ]; then
  mkdir -p logs
  if ! EXTRA_CXXFLAGS="$FLAGS" OUT=$OUT BACKEND=posix ./build_macos.sh >logs/$OUT-build.txt 2>&1; then
    echo "build failed, see logs/$OUT-build.txt"; exit 2
  fi
fi
[ -x "./$OUT" ] || { echo "no binary ./$OUT"; exit 2; }
BASE="logs/$OUT-runs-$$"; mkdir -p "$BASE"
calls=0; bad=0; unr=0; cut=0
for seed in 1 3 6 8 16; do
  outf="$BASE/seed-$seed.out"
  INCURSION_BIN="./$OUT" INCURSION_OPTIONS=tools/gates/Options.Dat \
    INCURSION_RUN_DIR="$BASE/run-$seed" INCURSION_MAP_AUDIT=0 \
    tools/run_capped.py 60 tools/headless.sh tools/keys/dive.keys $seed >"$outf" 2>&1
  rc=$?
  if [ "$rc" -eq 124 ]; then cut=$((cut+1)); echo "seed $seed: budget reached at 60 s (partial counts)"; fi
  line=$(grep -a '^REUSE_SELFCHECK ' "$outf" | tail -1)
  if [ -z "$line" ]; then echo "seed $seed: no REUSE_SELFCHECK line (see $outf)"; exit 2; fi
  c=${line#*reuses=}; c=${c%% *}
  b=${line#*bad=}; b=${b%% *}
  u=${line##*unreachable=}
  echo "seed $seed: reuses=$c bad=$b unreachable=$u"
  calls=$((calls+c)); bad=$((bad+b)); unr=$((unr+u))
done
echo "total reuses=$calls bad=$bad unreachable=$unr budget-cut seeds=$cut of 5"
[ "$calls" -gt 1000 ] || { echo "FAIL: too few reuses to judge"; exit 2; }
if [ $RED = 1 ]; then
  if [ "$bad" -gt 0 ]; then echo "PROVED RED"; exit 0; fi
  echo "NOT RED: skipping the RunOver test produced no bad reuse"; exit 1
fi
[ "$bad" -eq 0 ] && { echo "PASS"; exit 0; }
echo "FAIL: a reuse left the stored route or stepped onto a refused square"; exit 1
