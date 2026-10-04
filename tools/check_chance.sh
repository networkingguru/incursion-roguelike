#!/bin/bash
# Regression check for inc-1xr3: the chance SkillCheckChance / SaveChance
# advertise must match what SkillCheck / SavingThrow actually do.
#
# The oracle is logs/chance_probe.log, written by ChanceProbeNote (src/Skills.cpp)
# under INCURSION_CHANCE_PROBE. Every line is
#
#   <skill|save> <sk-or-type> <DC> <predicted%> <result 0/1>
#
# where predicted% was computed with SkillCheckChance / SaveChance from the
# SAME arguments, before the die was rolled.
#
# THE RULES BEING CHECKED
#
# (a) every line with predicted 0 must have result 0, and every line with
#     predicted 100 must have result 1;
# (b) for each 10-point bucket of predicted chance holding at least 30 lines,
#     the observed success rate must be within 15 points of the bucket's mean
#     predicted chance.
#
# It fails if it finds no probe lines at all, or if the number of run
# directories found differs from the number of runs.
#
# Usage: tools/check_chance.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEEDS="4242 7 99"
OPTS=tools/fixtures/options-2026-08-22.dat
KEYS=tools/keys/dive.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BASE="$ROOT/logs/chance-check-$STAMP"
mkdir -p "$BASE"

for s in $SEEDS; do
    rd="$BASE/run-$s"
    INCURSION_CHANCE_PROBE=1 INCURSION_OPTIONS="$OPTS" \
        INCURSION_RUN_DIR="$rd" \
        tools/headless.sh "$KEYS" "$s" > "$rd.headless.log" 2>&1
done

# Collect every probe log from the run dirs we just made.
RUNCOUNT=0
for s in $SEEDS; do
    [ -d "$BASE/run-$s" ] && RUNCOUNT=$((RUNCOUNT + 1))
done

NRUNS=$(echo $SEEDS | wc -w | tr -d ' ')
if [ "$RUNCOUNT" != "$NRUNS" ]; then
    echo "FAIL: found $RUNCOUNT run dirs, expected $NRUNS"
    exit 1
fi

LOGS="$(ls "$BASE"/run-*/logs/chance_probe.log 2>/dev/null)"
if [ -z "$LOGS" ]; then
    echo "FAIL: no probe lines at all (no chance_probe.log under $BASE)"
    exit 1
fi

cat $LOGS > "$BASE/all.log"
TOTAL=$(grep -c . "$BASE/all.log" 2>/dev/null || echo 0)
if [ "$TOTAL" = "0" ]; then
    echo "FAIL: no probe lines at all (0 lines)"
    exit 1
fi

awk -v total="$TOTAL" '
{
    pred = $4 + 0
    res  = $5 + 0
    lines++
    # bucket: floor(pred/10)*10
    b = int(pred/10)*10
    bcount[b]++
    bsum[b] += pred
    bok[b] += res
    # (a)
    if (pred == 0 && res != 0) { hard++; print "  predicted 0 but result " res ": " $0 }
    if (pred == 100 && res != 1) { hard++; print "  predicted 100 but result " res ": " $0 }
}
END {
    buckets = 0
    fails = 0
    for (b in bcount) {
        if (bcount[b] < 30) continue
        buckets++
        mean = bsum[b] / bcount[b]
        obs = 100.0 * bok[b] / bcount[b]
        d = obs - mean
        if (d < 0) d = -d
        if (d > 15) {
            fails++
            printf "  bucket %3d-%3d: %d lines, mean %.1f%%, observed %.1f%%, drift %.1f\n",
                b, b+9, bcount[b], mean, obs, d
        }
    }
    printf "lines: %d\n", lines
    printf "buckets checked: %d\n", buckets
    printf "failures: %d (hard %d, bucket %d)\n", hard+fails, hard, fails
    exit (hard+fails) ? 1 : 0
}' "$BASE/all.log"
rc=$?

# If (b) had no bucket with 30 lines, say so and report counts per bucket.
if [ $rc -eq 0 ]; then
    awk '
    { b = int(($4+0)/10)*10; bcount[b]++ }
    END {
        n = 0
        for (b in bcount) if (bcount[b] >= 30) n++
        if (n == 0) {
            printf "NOTE: no bucket has 30 lines; per-bucket line counts:\n"
            for (b in bcount) printf "  %3d-%3d: %d\n", b, b+9, bcount[b]
        }
    }' "$BASE/all.log"
fi

exit $rc
