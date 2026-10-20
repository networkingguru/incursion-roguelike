#!/bin/bash
# inc-zgww: end a Wild Shape form after a damaging fight and read the hit points.
# Usage: tools/formend_hp.sh <waits> <seed> [<seed> ...]
#   <waits> = turns an adjacent ogre gets at the Wild Shape (black bear) form.
# One row per seed: seed | in-form HP before | HP after | messages.
# Specimens: logs/formend/<waits>-<seed>/ (screen dumps), under logs/ only.
set -u
fail=0
cd "$(dirname "$0")/.." || exit 2
waits=${1:?waits}; shift
mkdir -p logs/formend
keys="logs/formend/formend-hp-$waits.keys"
sed "s/^\.\*WAITS\$/.*$waits/" tools/keys/formend-hp.keys > "$keys"
for seed in "$@"; do
  run="logs/formend/$waits-$seed"
  rm -rf "$run"
  INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
  INCURSION_LOAD=tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav \
  INCURSION_RUN_DIR="$run" tools/headless.sh "$keys" "$seed" > "$run.out" 2>&1
  s="$run/logs/screens"
  b=$(grep -m1 '^HP:' "$s"/*-before-end.txt | cut -d' ' -f1)
  a=$(grep -m1 '^HP:' "$s"/*-after-end.txt | cut -d' ' -f1)
  m=$(sed -n 1,3p "$s"/*-after-end.txt | tr -s ' \n' ' ' | cut -c1-110)
  echo "seed $seed | before $b | after $a | $m"
  # Expected: pct = cur*100/formMax; want = max(pct*normalMax/100, 1), integer
  # division throughout (the arithmetic Creature::Shapeshift uses). Fails on a
  # mismatch, on an unreadable HP line, or on a death/stagger message.
  if [[ "$b" =~ ^HP:([0-9]+)/([0-9]+)$ ]]; then bc=${BASH_REMATCH[1]}; bm=${BASH_REMATCH[2]}; else bc=; fi
  if [[ "$a" =~ ^HP:([0-9]+)/([0-9]+)$ ]]; then ac=${BASH_REMATCH[1]}; am=${BASH_REMATCH[2]}; else ac=; fi
  if [ -z "$bc" ] || [ -z "$ac" ]; then echo "  FAIL seed $seed: HP line unreadable"; fail=1; continue; fi
  want=$(( (bc * 100 / bm) * am / 100 )); [ "$want" -lt 1 ] && want=1
  if [ "$ac" -ne "$want" ]; then echo "  FAIL seed $seed: after $ac, want $want ($bc/$bm share of $am)"; fail=1; fi
  if grep -rliE 'drop dead|stagger' "$run/logs/screens" > /dev/null 2>&1; then
    echo "  FAIL seed $seed: death/stagger message"; fail=1; fi
done
[ "$fail" -eq 0 ] && echo "PASS" || echo "FAILED"
exit "$fail"
