#!/bin/bash
# inc-9w9y: what does it cost to let every creature on the map act each turn?
#
# Usage: tools/measure_all_act.sh [sessions] [first-seed] [keyscript]
#        (defaults: 40 1 tools/keys/dive.keys -- the gate's own seeds)
#
# Plays the same seeds twice, one session at a time, with the gate's pinned
# settings: once as shipped, once with INCURSION_ALL_ACT=1 (src/Main.cpp lifts
# the MaxDist distance test so every creature acts). Records per seed and per
# arm: wall seconds, the turn stamp of the last screen dump, died or survived
# (the gate's own test, tools/gate_lib.sh), exit code and error/ASSERT lines.
# Output: logs/measure-all-act/<stamp>-<pid>/{off,on}/seed-N, results.tsv.
# The "off" arm is meant to be read with: tools/gate_compare.sh --from <off dir>
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
. "$ROOT/tools/gate_lib.sh"

SESSIONS="${1:-40}"
FIRST="${2:-1}"
KEYS="${3:-tools/keys/dive.keys}"
[ -f "$KEYS" ] || { echo "no such key script: $KEYS"; exit 2; }
[ -x ./incursion-headless ] || { echo "build first: BACKEND=posix ./build_macos.sh"; exit 2; }
[ -f "$GATE_OPTIONS" ] || { echo "missing $GATE_OPTIONS"; exit 2; }

until tools/load_guard.sh; do sleep 30; done

OUT="$ROOT/logs/measure-all-act/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT/off" "$OUT/on"
TSV="$OUT/results.tsv"
printf 'arm\tseed\twall_s\tturns\tdied\texit\terr_lines\tassert_lines\n' > "$TSV"
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

RUNS=0
for seed in $(seq "$FIRST" $((FIRST + SESSIONS - 1))); do
    for arm in off on; do
        run="$OUT/$arm/seed-$seed"
        t0="$(now)"
        if [ "$arm" = on ]; then
            INCURSION_ALL_ACT=1 INCURSION_OPTIONS="$GATE_OPTIONS" INCURSION_RUN_DIR="$run" \
                ./tools/headless.sh "$KEYS" "$seed" > "$run.out" 2>&1
        else
            env -u INCURSION_ALL_ACT INCURSION_OPTIONS="$GATE_OPTIONS" INCURSION_RUN_DIR="$run" \
                ./tools/headless.sh "$KEYS" "$seed" > "$run.out" 2>&1
        fi
        code=$?
        t1="$(now)"
        echo "$seed $code" >> "$OUT/$arm/exits"
        RUNS=$((RUNS + 1))
        wall="$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')"
        turns=0
        for f in "$run"/logs/screens/*.txt; do
            [ -f "$f" ] || continue
            n="$(sed -n '1s/.*turn \([0-9]*\).*/\1/p' "$f")"
            [ -n "$n" ] && [ "$n" -gt "$turns" ] && turns="$n"
        done
        died=0
        [ -f "$run/logs/death.log" ] && died=1
        if [ "$died" -eq 0 ]; then
            last="$(ls "$run/logs/screens" 2>/dev/null | sort | tail -1)"
            [ -n "$last" ] && grep -q 'Die? \[yn\]' "$run/logs/screens/$last" 2>/dev/null && died=1
        fi
        el=0; as=0
        if [ -f "$run/logs/errors.log" ]; then
            el="$(grep -c '^[0-9]' "$run/logs/errors.log")"
            as="$(grep -c 'ASSERT failed' "$run/logs/errors.log")"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$arm" "$seed" "$wall" "$turns" "$died" "$code" "$el" "$as" >> "$TSV"
    done
done

DIRS="$(find "$OUT/off" "$OUT/on" -maxdepth 1 -type d -name 'seed-*' | wc -l | tr -d ' ')"
echo "run dirs: $DIRS, runs: $RUNS"
[ "$DIRS" -eq "$RUNS" ] || { echo "ASSERT: run-dir count $DIRS != runs $RUNS"; exit 1; }

for arm in off on; do
    awk -F'\t' -v a="$arm" '$1==a {print $3}' "$TSV" | sort -n > "$OUT/$arm.walls"
done
echo "=== summary ($OUT)"
for arm in off on; do
    awk -F'\t' -v a="$arm" -v wf="$OUT/$arm.walls" '
        BEGIN { while ((getline x < wf) > 0) w[++n] = x
                med = (n % 2) ? w[(n+1)/2] : (w[n/2] + w[n/2+1]) / 2 }
        $1==a { tw += $3; tt += $4; d += $5; e += $7; s += $8; if ($6 != 0) bad++ }
        END { printf "%-3s wall total %.1fs median %.2fs | turns %d | died %d/%d | err lines %d (ASSERT %d) | nonzero exits %d\n", a, tw, med, tt, d, n, e, s, bad }' "$TSV"
done
awk -F'\t' '$1=="off" {tw0 += $3; m0[$2]=$3; d0[$2]=$5; t0[$2]=$4}
            $1=="on"  {tw1 += $3; m1[$2]=$3; d1[$2]=$5; t1[$2]=$4}
            END { printf "wall ratio on/off: %.3f\n", tw1/tw0
                  for (s in d0) if (d0[s] != d1[s]) printf "outcome changed seed %s: off died=%s on died=%s (turns %s -> %s)\n", s, d0[s], d1[s], t0[s], t1[s] }' "$TSV" | sort -V
