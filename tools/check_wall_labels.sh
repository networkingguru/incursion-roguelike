#!/bin/bash
# gate: live
# Does Map::ShortestPath refuse a route only when walls really separate start
# and target? (inc-vhkei)
#
# A build with -DLABEL_SELFCHECK still runs the full search whenever the
# wall-label test would refuse, counts a mismatch if the search reaches the
# target (LABEL_MISMATCH) and prints LABEL_SELFCHECK refusals=<n> mismatches=<m>
# (every 1000 refusals and at exit). This check runs dive.keys on seeds
# 1 3 6 8 16 and FAILS unless every run printed the summary line, total
# refusals exceed 100 and mismatches are 0.
#
# fact: which routes are refused -- none; the self-check compares every label refusal with the full search, whatever the seed plays
# fact: settings -- tools/gates/Options.Dat
# fact: run isolation -- unique INCURSION_RUN_DIR per run
# fact: how long a seed runs -- 60 s is a per-seed sampling budget (the summary line prints every
#   1000 calls, so a cut run still counts); tools/run_capped.py enforces it on the whole process
#   group, and a hang is bounded by the same limit
#
# Usage: tools/check_wall_labels.sh [--no-build] [--prove-red]
# --prove-red: build with -DLABEL_BREAK (labels flood 4-connected, so areas
# joined only diagonally are wrongly split) and require mismatches > 0,
# printing PROVED RED.
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
OUT=incursion-label-check; FLAGS=-DLABEL_SELFCHECK
if [ $RED = 1 ]; then OUT=incursion-label-red; FLAGS="-DLABEL_SELFCHECK -DLABEL_BREAK"; fi
if [ $BUILD = 1 ]; then
  mkdir -p logs
  if ! EXTRA_CXXFLAGS="$FLAGS" OUT=$OUT BACKEND=posix ./build_macos.sh >logs/$OUT-build.txt 2>&1; then
    echo "build failed, see logs/$OUT-build.txt"; exit 2
  fi
fi
[ -x "./$OUT" ] || { echo "no binary ./$OUT"; exit 2; }
BASE="logs/$OUT-runs-$$"; mkdir -p "$BASE"
calls=0; mis=0; cut=0
for seed in 1 3 6 8 16; do
  outf="$BASE/seed-$seed.out"
  INCURSION_BIN="./$OUT" INCURSION_OPTIONS=tools/gates/Options.Dat \
    INCURSION_RUN_DIR="$BASE/run-$seed" INCURSION_MAP_AUDIT=0 \
    tools/run_capped.py 60 tools/headless.sh tools/keys/dive.keys $seed >"$outf" 2>&1
  rc=$?
  if [ "$rc" -eq 124 ]; then cut=$((cut+1)); echo "seed $seed: budget reached at 60 s (partial counts)"; fi
  line=$(grep -a '^LABEL_SELFCHECK ' "$outf" | tail -1)
  if [ -z "$line" ]; then echo "seed $seed: no LABEL_SELFCHECK line (see $outf)"; exit 2; fi
  c=${line#*refusals=}; c=${c%% *}; m=${line##*mismatches=}
  echo "seed $seed: refusals=$c mismatches=$m"
  calls=$((calls+c)); mis=$((mis+m))
done
echo "total refusals=$calls mismatches=$mis budget-cut seeds=$cut of 5"
[ "$calls" -gt 100 ] || { echo "FAIL: too few refusals to judge"; exit 2; }
if [ $RED = 1 ]; then
  if [ "$mis" -gt 0 ]; then echo "PROVED RED"; exit 0; fi
  echo "NOT RED: 4-connected labels produced no mismatch"; exit 1
fi
[ "$mis" -eq 0 ] && { echo "PASS"; exit 0; }
echo "FAIL: label refusal for a reachable target"; exit 1
