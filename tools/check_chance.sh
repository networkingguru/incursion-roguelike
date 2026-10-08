#!/bin/bash
# gate: live
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
#     and for the pooled set of every line with 0 < predicted < 100, the
#     results must be consistent with each line's own predicted probability
#     p_i = predicted%/100. With E = sum p_i, V = sum p_i*(1-p_i) and
#     O = sum results, z = (O - E) / sqrt(V); a test fails when |z| > 4.
#     A test whose V is 0 is skipped. The pooled test keeps power against a
#     systematic offset that no single bucket shows.
#
# It fails if it finds no probe lines at all, or if the number of run
# directories found differs from the number of runs.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation adds
# a constant +5 to the roll side of SkillCheck's success test (src/Skills.cpp),
# so the roll succeeds more often than SkillCheckChance predicts; the pooled
# z then grows past 4 and this check exits 1.
#
# Usage: tools/check_chance.sh [--prove-red]  (0 pass, 1 fail)
. "$(dirname "$0")/check_lib.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The mutation this check defends: make SkillCheck's success test easier by a
# fixed +5 on the roll side, so the die succeeds more often than the chance we
# advertise. Declared before the (build-needing) measurement below so
# --prove-red intercepts here.
check_mutation src/Skills.cpp \
'	bool succ = (sr + roll + mod1 + mod2 + armPen) >= DC;' \
'	bool succ = (sr + roll + 5 + mod1 + mod2 + armPen) >= DC;'

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
    p    = pred / 100.0
    lines++
    # bucket: floor(pred/10)*10
    b = int(pred/10)*10
    bn[b]++
    bE[b] += p
    bV[b] += p * (1.0 - p)
    bO[b] += res
    # (a)
    if (pred == 0 && res != 0) { hard++; print "  predicted 0 but result " res ": " $0 }
    if (pred == 100 && res != 1) { hard++; print "  predicted 100 but result " res ": " $0 }
    # pooled set: strictly between 0 and 100
    if (pred > 0 && pred < 100) {
        pn++
        pE += p
        pV += p * (1.0 - p)
        pO += res
    }
}
END {
    buckets = 0
    fails = 0
    zfails = 0
    pzfail = 0
    for (b in bn) {
        if (bn[b] < 30) continue
        buckets++
        if (bV[b] <= 0) continue
        z = (bO[b] - bE[b]) / sqrt(bV[b])
        printf "  bucket %3d-%3d: n=%d E=%.2f O=%.0f z=%+.3f\n",
            b, b+9, bn[b], bE[b], bO[b], z
        if (z < 0) zz = -z; else zz = z
        if (zz > 4) {
            fails++
            zfails++
            printf "  bucket %3d-%3d FAILS: |z|=%.3f > 4\n", b, b+9, zz
        }
    }
    if (pV > 0) {
        pz = (pO - pE) / sqrt(pV)
        printf "  pooled: n=%d E=%.2f O=%.0f z=%+.3f\n", pn, pE, pO, pz
        if (pz < 0) pzz = -pz; else pzz = pz
        if (pzz > 4) {
            fails++
            pzfail = 1
            printf "  pooled FAILS: |z|=%.3f > 4\n", pzz
        }
    } else {
        printf "  pooled: skipped (V=0)\n"
    }
    printf "lines: %d\n", lines
    printf "buckets checked: %d\n", buckets
    printf "failures: %d (hard %d, bucket %d, pooled %d)\n", hard+fails, hard,
        zfails, pzfail
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
