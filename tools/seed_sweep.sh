#!/usr/bin/env bash
# gate: none <why: it runs other checks; it is a tool, not a check>
#
# Does a check give the same verdict on other seeds? (inc-ug5y)
#   tools/seed_sweep.sh [--classify] <tools/check_X.sh> [--seeds "101 202 303 404 505"]
# Exit 0 seed-independent or no game played, 1 seed-dependent, 2 unmeasured/usage.
# --classify: a failing control does not stop the sweep. Exit 0 all runs pass,
# 1 mixed, 3 no run passed (seed not the cause), 2 unmeasured.
# Uses INCURSION_SEED_OVERRIDE and INCURSION_SEED_LOG in tools/headless.sh.
# See docs/VERIFICATION.md, "A check must not depend on the seed".

usage() { echo "usage: tools/seed_sweep.sh [--classify] <tools/check_X.sh> [--seeds \"101 202 ...\"]" >&2; exit 2; }

CHECK=""
CLASSIFY=0
SEEDS="101 202 303 404 505"
while [ $# -gt 0 ]; do
    case "$1" in
        --seeds) [ $# -ge 2 ] || usage; SEEDS="$2"; shift 2 ;;
        --classify) CLASSIFY=1; shift ;;
        -*) usage ;;
        *) [ -z "$CHECK" ] || usage; CHECK="$1"; shift ;;
    esac
done
[ -n "$CHECK" ] && [ -f "$CHECK" ] || usage
[ -n "$SEEDS" ] || usage

cd "$(dirname "$0")/.." || exit 2
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
for s in $SEEDS; do
    total=$((total + 1))
    : > "$TMP/seed.log"
    INCURSION_SEED_OVERRIDE="$s" INCURSION_SEED_LOG="$TMP/seed.log" \
        bash "$CHECK" > "$OUT/seed-$s.txt" 2>&1
    rc=$?
    lines=$(grep -c . "$TMP/seed.log")
    match=$(grep -c "^seed=$s keys=" "$TMP/seed.log")
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
done

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
