#!/usr/bin/env bash
# gate: none <why: it runs other checks; it is a tool, not a check>
#
# Does a check give the same verdict on other seeds? (inc-ug5y)
#   tools/seed_sweep.sh [--classify] <tools/check_X.sh> [--seeds "101 202 303 404 505"]
#                       [--slots "DIR1 DIR2 ..."]
# Exit 0 seed-independent or no game played, 1 seed-dependent, 2 unmeasured/usage.
# --classify: a failing control does not stop the sweep. Exit 0 all runs pass,
# 1 mixed, 3 no run passed (seed not the cause), 2 unmeasured.
# --slots: run the seeds at the same time, seed i in directory i. Each DIR is a
# full checkout of this tree holding the check at the same path. The number of
# DIRs MUST equal the number of seeds. The control run stays alone, first, here.
# Uses INCURSION_SEED_OVERRIDE and INCURSION_SEED_LOG in tools/headless.sh.
# See docs/VERIFICATION.md, "A check must not depend on the seed".

usage() { echo "usage: tools/seed_sweep.sh [--classify] <tools/check_X.sh> [--seeds \"101 202 ...\"] [--slots \"DIR1 DIR2 ...\"]" >&2; exit 2; }

CHECK=""
CLASSIFY=0
SEEDS="101 202 303 404 505"
SLOTS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --seeds) [ $# -ge 2 ] || usage; SEEDS="$2"; shift 2 ;;
        --slots) [ $# -ge 2 ] || usage; SLOTS="$2"; shift 2 ;;
        --classify) CLASSIFY=1; shift ;;
        -*) usage ;;
        *) [ -z "$CHECK" ] || usage; CHECK="$1"; shift ;;
    esac
done
[ -n "$CHECK" ] && [ -f "$CHECK" ] || usage
[ -n "$SEEDS" ] || usage

cd "$(dirname "$0")/.." || exit 2
ROOT="$PWD"
if [ -n "$SLOTS" ]; then
    set -- $SLOTS
    nslots=$#
    set -- $SEEDS
    [ "$nslots" -eq "$#" ] || { echo "--slots needs one directory per seed ($nslots dirs, $# seeds)" >&2; usage; }
fi
NAME="$(basename "$CHECK" .sh)"
OUT="logs/seed-sweep/$NAME-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" || exit 2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "outputs: $OUT"

: > "$TMP/control.log"
INCURSION_SEED_LOG="$TMP/control.log" bash "$CHECK" > "$OUT/control.txt" 2>&1
rc=$?
if [ ! -s "$TMP/control.log" ]; then
    echo "NOT SEED-DRIVEN: $CHECK runs no headless session"
    exit 0
fi
ctl_rc=$rc
if [ "$rc" -ne 0 ] && [ "$CLASSIFY" -eq 0 ]; then
    echo "UNMEASURED: control run on own seed exited $rc"
    exit 2
fi

total=0
bad=0
[ "$CLASSIFY" -eq 1 ] && [ "$ctl_rc" -ne 0 ] && bad=1
[ "$CLASSIFY" -eq 1 ] && total=1

# Judge one finished seed run: sets rc in the caller, counts it, prints its line.
# Usage: evaluate_seed <seed> <rc> <seed-log>
evaluate_seed() {
    local s="$1" rc="$2" log="$3" lines match word verdict
    total=$((total + 1))
    lines=$(grep -c . "$log")
    match=$(grep -c "^seed=$s keys=" "$log")
    if [ "$lines" -lt 1 ] || [ "$lines" -ne "$match" ]; then
        echo "UNMEASURED: override did not reach the harness for seed $s"
        exit 2
    fi
    case "$rc" in
        0) word="PASS" ;;
        2) word="INCONCLUSIVE rc=2" ;;
        *) word="FAIL rc=$rc" ;;
    esac
    [ "$rc" -eq 0 ] || bad=$((bad + 1))
    verdict=$(grep -E 'PASS|FAIL|INCONCLUSIVE|UNMEASURED' "$OUT/seed-$s.txt" | tail -1 | cut -c1-200)
    echo "seed $s: $word  $verdict"
}

if [ -z "$SLOTS" ]; then
    for s in $SEEDS; do
        : > "$TMP/seed.log"
        INCURSION_SEED_OVERRIDE="$s" INCURSION_SEED_LOG="$TMP/seed.log" \
            bash "$CHECK" > "$OUT/seed-$s.txt" 2>&1
        evaluate_seed "$s" "$?" "$TMP/seed.log"
    done
else
    case "$CHECK" in /*) rel="${CHECK#"$ROOT"/}" ;; *) rel="$CHECK" ;; esac
    for d in $SLOTS; do
        if [ ! -f "$d/$rel" ]; then
            echo "slot $d has no $rel" >&2
            exit 2
        fi
    done
    pids=()
    set -- $SLOTS
    for s in $SEEDS; do
        dir="$1"; shift
        : > "$TMP/seed-$s.log"
        ( cd "$dir" && INCURSION_SEED_OVERRIDE="$s" INCURSION_SEED_LOG="$TMP/seed-$s.log" \
            bash "$rel" ) > "$OUT/seed-$s.txt" 2>&1 &
        pids+=("$!")
    done
    i=0
    for s in $SEEDS; do
        wait "${pids[$i]}"
        rcs[$i]=$?
        i=$((i + 1))
    done
    i=0
    for s in $SEEDS; do
        evaluate_seed "$s" "${rcs[$i]}" "$TMP/seed-$s.log"
        i=$((i + 1))
    done
fi

if [ "$CLASSIFY" -eq 1 ] && [ "$bad" -gt 0 ]; then
    if [ "$bad" -eq "$total" ]; then
        echo "FAILS ON EVERY SEED: $total runs"
        exit 3
    fi
    echo "SEED-DEPENDENT: passes on $((total - bad)) of $total runs"
    exit 1
fi
if [ "$bad" -eq 0 ]; then
    echo "SEED-INDEPENDENT on $total seeds"
    exit 0
fi
echo "SEED-DEPENDENT: $bad of $total seeds did not pass"
exit 1
