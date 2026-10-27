#!/bin/bash
# gate: live
# Does Map::ShortestPath (A*, src/Djikstra.cpp) return the same reachability and
# the same cost to the target as plain Dijkstra? (inc-vhkei)
#
# A build with -DASTAR_SELFCHECK reruns plain Dijkstra after every A* search and
# compares Dist[target]. It prints ASTAR_MISMATCH per difference and, at exit,
# ASTAR_SELFCHECK calls=<n> mismatches=<m> (src/AStarSelfCheck.h).
# The summary is also printed every 1000 calls, so a run the timeout kills still reports.
# This check runs dive.keys on seeds 1 3 6 8 16 and FAILS unless every run
# printed the summary line, the total calls exceed 1000 and mismatches are 0.
#
# fact: which routes are searched -- none; the self-check compares A* with Dijkstra on every call, whatever the seed plays
# fact: settings -- tools/gates/Options.Dat
# fact: run isolation -- unique INCURSION_RUN_DIR per run
# fact: a hang -- 60 s wall timeout per run
#
# Usage: tools/check_astar_cost.sh [--no-build] [--prove-red]
# --prove-red: build with -DASTAR_OVERESTIMATE (heuristic x4, inadmissible) and
# require mismatches > 0, printing PROVED RED.
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
OUT=incursion-astar-check; FLAGS=-DASTAR_SELFCHECK
if [ $RED = 1 ]; then OUT=incursion-astar-red; FLAGS="-DASTAR_SELFCHECK -DASTAR_OVERESTIMATE"; fi
if [ $BUILD = 1 ]; then
  mkdir -p logs
  if ! EXTRA_CXXFLAGS="$FLAGS" OUT=$OUT BACKEND=posix ./build_macos.sh >logs/$OUT-build.txt 2>&1; then
    echo "build failed, see logs/$OUT-build.txt"; exit 2
  fi
fi
[ -x "./$OUT" ] || { echo "no binary ./$OUT"; exit 2; }
BASE="logs/$OUT-runs-$$"; mkdir -p "$BASE"
calls=0; mis=0
for seed in 1 3 6 8 16; do
  outf="$BASE/seed-$seed.out"
  INCURSION_BIN="./$OUT" INCURSION_OPTIONS=tools/gates/Options.Dat \
    INCURSION_RUN_DIR="$BASE/run-$seed" INCURSION_MAP_AUDIT=0 \
    perl -e 'alarm 60; exec @ARGV' tools/headless.sh tools/keys/dive.keys $seed >"$outf" 2>&1
  line=$(grep -a '^ASTAR_SELFCHECK ' "$outf" | tail -1)
  if [ -z "$line" ]; then echo "seed $seed: no ASTAR_SELFCHECK line (see $outf)"; exit 2; fi
  c=${line#*calls=}; c=${c%% *}; m=${line##*mismatches=}
  echo "seed $seed: calls=$c mismatches=$m"
  calls=$((calls+c)); mis=$((mis+m))
done
echo "total calls=$calls mismatches=$mis"
[ "$calls" -gt 1000 ] || { echo "FAIL: too few calls to judge"; exit 2; }
if [ $RED = 1 ]; then
  if [ "$mis" -gt 0 ]; then echo "PROVED RED"; exit 0; fi
  echo "NOT RED: inadmissible heuristic produced no mismatch"; exit 1
fi
[ "$mis" -eq 0 ] && { echo "PASS"; exit 0; }
echo "FAIL: A* cost differs from Dijkstra"; exit 1
