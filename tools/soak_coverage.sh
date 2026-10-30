#!/bin/bash
# inc-b0ziu.1: measure which C++ functions and script routines the landing
# gate's soak (tools/keys/dive.keys under tools/gates/Options.Dat) reaches.
#
#   tools/soak_coverage.sh [sessions] <out-dir>      sessions defaults to 40
#   tools/soak_coverage.sh <out-dir>                 same, 40 sessions
#
# Builds nothing. Needs the clang coverage build:
#   EXTRA_CXXFLAGS="-fprofile-instr-generate -fcoverage-mapping" \
#     EXTRA_LDFLAGS=-fprofile-instr-generate OUT=incursion-cov \
#     BACKEND=posix ./build_macos.sh
# Writes to <out-dir>: functions.txt (sorted, demangled C++ functions with a
# nonzero count), common-functions.txt and common-routines.txt (in EVERY session), routines.txt (sorted union of every session's
# logs/scriptcov.log, "<resource>\t<event>"), summary.txt, and runs/seed-N/.
#
# Exit: 0 done; 1 a session wrote no .profraw or no scriptcov.log (the seed is
#       named); 2 could not start (no build, bad arguments, missing tool).
#
# fact: character -- the soak's own: dive.keys on the seed builds it; this tool measures the soak, so it takes the soak's seeds on purpose
# fact: settings -- INCURSION_OPTIONS=tools/gates/Options.Dat
# fact: key script -- tools/keys/dive.keys
# fact: run directory -- unique INCURSION_RUN_DIR per session
# fact: whether a session produced coverage files -- asserted per seed, a missing file fails the tool whatever the seed
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ $# -eq 2 ]; then N="$1"; OUT="$2"; elif [ $# -eq 1 ]; then N=40; OUT="$1"
else echo "usage: tools/soak_coverage.sh [sessions] <out-dir>"; exit 2; fi
case "$N" in ''|*[!0-9]*|0) echo "sessions must be a positive integer: $N"; exit 2 ;; esac

if [ ! -x ./incursion-cov ]; then
    echo "./incursion-cov not built. Run:"
    echo '  EXTRA_CXXFLAGS="-fprofile-instr-generate -fcoverage-mapping" EXTRA_LDFLAGS=-fprofile-instr-generate OUT=incursion-cov BACKEND=posix ./build_macos.sh'
    exit 2
fi
for t in llvm-profdata llvm-cov; do
    xcrun --find "$t" >/dev/null 2>&1 || { echo "xcrun cannot find $t"; exit 2; }
done

mkdir -p "$OUT" || exit 2
OUT="$(cd "$OUT" && pwd)"
RUNS="$OUT/runs"
# SOAK_COV_REUSE=1 skips the sessions and judges the runs already in <out-dir>
# (the red proof deletes one file and re-judges).
if [ "${SOAK_COV_REUSE:-0}" != 1 ]; then rm -rf "$RUNS"; mkdir -p "$RUNS"; fi
JOBS="${SOAK_JOBS:-4}"

run_one() {
    local seed="$1" d="$RUNS/seed-$1"
    INCURSION_BIN=./incursion-cov \
    INCURSION_OPTIONS=tools/gates/Options.Dat \
    INCURSION_SCRIPT_COV=1 \
    INCURSION_RUN_DIR="$d" \
    LLVM_PROFILE_FILE="$d/logs/cov-%p.profraw" \
        ./tools/headless.sh tools/keys/dive.keys "$seed" > "$RUNS/seed-$seed.out" 2>&1
    echo "$seed $?" >> "$RUNS/exits"
}

START=$(date +%s)
# bash 3.2 (macOS /bin/bash) has no `wait -n`, so poll the pids instead.
live_count() {
    local p n=0
    for p in "$@"; do kill -0 "$p" 2>/dev/null && n=$((n + 1)); done
    printf '%s' "$n"
}
pids=""
for seed in $(seq 1 "$N"); do
    [ "${SOAK_COV_REUSE:-0}" = 1 ] && break
    mkdir -p "$RUNS/seed-$seed/logs"
    while [ "$(live_count $pids)" -ge "$JOBS" ]; do sleep 0.2; done
    run_one "$seed" &
    pids="$pids $!"
done
wait
ELAPSED=$(( $(date +%s) - START ))

BAD=0
for seed in $(seq 1 "$N"); do
    d="$RUNS/seed-$seed/logs"
    ls "$d"/*.profraw >/dev/null 2>&1 || { echo "seed $seed: no .profraw"; BAD=1; }
    [ -f "$d/scriptcov.log" ] || { echo "seed $seed: no scriptcov.log"; BAD=1; }
done
[ "$BAD" -eq 0 ] || exit 1

export_one() {
    local seed="$1" d="$RUNS/seed-$1"
    xcrun llvm-profdata merge -o "$d/cov.profdata" "$d"/logs/*.profraw || return 1
    xcrun llvm-profdata show --all-functions "$d/cov.profdata" |
        awk '/^  [^ ].*:$/ { n = substr($0, 3, length($0) - 3) }
             /^    Function count: / { if ($3 > 0) print n }' |
        xcrun c++filt | LC_ALL=C sort -u > "$d/functions.txt"
    LC_ALL=C sort -u "$d/logs/scriptcov.log" > "$d/routines.txt"
}
XSTART=$(date +%s)
pids=""
for seed in $(seq 1 "$N"); do
    while [ "$(live_count $pids)" -ge "$JOBS" ]; do sleep 0.2; done
    export_one "$seed" || { echo "seed $seed: coverage export failed"; exit 2; } &
    pids="$pids $!"
done
wait
for seed in $(seq 1 "$N"); do
    [ -f "$RUNS/seed-$seed/functions.txt" ] || { echo "seed $seed: export wrote no functions.txt"; exit 2; }
done
XELAPSED=$(( $(date +%s) - XSTART ))

# union: in any session; common: in every session (comm needs sorted input)
for kind in functions routines; do
    cat "$RUNS"/seed-*/$kind.txt | LC_ALL=C sort -u > "$OUT/$kind.txt"
    LC_ALL=C sort -u "$RUNS/seed-1/$kind.txt" > "$OUT/common-$kind.txt"
    for seed in $(seq 2 "$N"); do
        LC_ALL=C comm -12 "$OUT/common-$kind.txt" "$RUNS/seed-$seed/$kind.txt" > "$OUT/common.tmp"
        mv "$OUT/common.tmp" "$OUT/common-$kind.txt"
    done
done

if [ "${SOAK_COV_REUSE:-0}" = 1 ]; then WALL="not measured (reuse)"; else WALL="${ELAPSED}s at $JOBS at a time"; fi
cnt() { wc -l < "$1" | tr -d ' '; }
{
    echo "sessions:  $N (seeds 1..$N, tools/keys/dive.keys, tools/gates/Options.Dat)"
    echo "wall time: $WALL"
    echo "export:    ${XELAPSED}s for $N sessions at $JOBS at a time"
    echo "functions: $(cnt "$OUT/functions.txt") in any session, $(cnt "$OUT/common-functions.txt") in every session"
    echo "routines:  $(cnt "$OUT/routines.txt") in any session, $(cnt "$OUT/common-routines.txt") in every session"
    for seed in $(seq 1 "$N"); do
        echo "seed $seed: $(cnt "$RUNS/seed-$seed/functions.txt") functions, $(cnt "$RUNS/seed-$seed/routines.txt") routines"
    done
} | tee "$OUT/summary.txt"
[ -s "$OUT/functions.txt" ] && [ -s "$OUT/routines.txt" ] || { echo "empty list"; exit 1; }
exit 0
