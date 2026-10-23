#!/usr/bin/env bash
# gate: none <why: it sweeps other checks for up to an hour; the nightly run calls it>
#
# Sweep a rotating slice of the live/smoke checks over other seeds. (inc-ug5y)
#   tools/nightly_seed_sweep.sh [--budget SECONDS] [--state FILE] [--report FILE]
# Report only: exit 0 whenever it ran, 2 when it cannot measure.
# Test-only overrides: NIGHTLY_SWEEP_CHECK_DIR, NIGHTLY_SWEEP_CMD, NIGHTLY_SWEEP_LOAD_GUARD.
# See docs/VERIFICATION.md, "A check must not depend on the seed".

cd "$(dirname "$0")/.." || exit 2
ROOT="$PWD"
BUDGET=3600
STATE="logs/seed-sweep/rotation.state"
DATE="$(date +%Y-%m-%d)"
REPORT="logs/seed-sweep/nightly-$DATE.md"
CHECK_DIR="${NIGHTLY_SWEEP_CHECK_DIR:-$ROOT/tools}"
SWEEP_CMD="${NIGHTLY_SWEEP_CMD:-$ROOT/tools/seed_sweep.sh}"
GUARD="${NIGHTLY_SWEEP_LOAD_GUARD:-$ROOT/tools/load_guard.sh}"

usage() { echo "usage: tools/nightly_seed_sweep.sh [--budget SECONDS] [--state FILE] [--report FILE]" >&2; exit 2; }
while [ $# -gt 0 ]; do
    case "$1" in
        --budget) [ $# -ge 2 ] || usage; BUDGET="$2"; shift 2 ;;
        --state) [ $# -ge 2 ] || usage; STATE="$2"; shift 2 ;;
        --report) [ $# -ge 2 ] || usage; REPORT="$2"; shift 2 ;;
        *) usage ;;
    esac
done
case "$BUDGET" in ''|*[!0-9]*) usage ;; esac

[ -x "$SWEEP_CMD" ] || { echo "UNMEASURED: sweep command missing: $SWEEP_CMD" >&2; exit 2; }

CANDS=()
while IFS= read -r f; do
    if head -40 "$f" | grep -qxE '# gate: (live|smoke)'; then CANDS+=("$(basename "$f")"); fi
done < <(find "$CHECK_DIR" -maxdepth 1 -name 'check_*.sh' | LC_ALL=C sort)
N=${#CANDS[@]}
[ "$N" -gt 0 ] || { echo "UNMEASURED: no live/smoke checks in $CHECK_DIR" >&2; exit 2; }

OUTDIR="$(dirname "$REPORT")/nightly-$DATE"
mkdir -p "$(dirname "$STATE")" "$OUTDIR" || { echo "UNMEASURED: cannot create output directories" >&2; exit 2; }
: >> "$STATE" && : > "$REPORT" || { echo "UNMEASURED: cannot write state or report" >&2; exit 2; }

START=0
LAST="$(head -1 "$STATE" 2>/dev/null)"
for i in "${!CANDS[@]}"; do
    [ "${CANDS[$i]}" = "$LAST" ] && START=$(( (i + 1) % N ))
done

indep=0; notdriven=0; dep=0; noans=0; swept=0
DEPLINES=(); NOLINES=()
STOP="full rotation ($N checks)"
for ((k = 0; k < N; k++)); do
    c="${CANDS[$(( (START + k) % N ))]}"
    spent=0
    until "$GUARD" > /dev/null 2>&1; do
        if [ "$SECONDS" -gt "$BUDGET" ]; then spent=1; break; fi
        sleep 30
    done
    if [ "$spent" -eq 1 ] || [ "$SECONDS" -gt "$BUDGET" ]; then
        STOP="budget spent before $c (${BUDGET}s)"
        break
    fi
    out="$OUTDIR/$c.txt"
    "$SWEEP_CMD" "$CHECK_DIR/$c" > "$out" 2>&1
    rc=$?
    swept=$((swept + 1))
    last="$(grep . "$out" | tail -1 | cut -c1-200)"
    case "$rc" in
        0) if grep -q 'NOT SEED-DRIVEN' "$out"; then notdriven=$((notdriven + 1)); else indep=$((indep + 1)); fi ;;
        1) dep=$((dep + 1)); DEPLINES+=("- \`$c\`: $last") ;;
        *) noans=$((noans + 1)); NOLINES+=("- \`$c\`: exit $rc") ;;
    esac
    echo "$c" > "$STATE" || { echo "UNMEASURED: cannot write state" >&2; exit 2; }
    LASTDONE="$c"
done
[ -n "${LASTDONE:-}" ] && STOP="$STOP; last swept ${LASTDONE}"

{
    echo "# Nightly seed sweep $DATE"
    echo
    echo "- swept: $swept"
    echo "- seed-independent: $indep"
    echo "- not seed-driven: $notdriven"
    echo "- seed-dependent: $dep"
    echo "- no answer: $noans"
    echo "- candidates total: $N"
    echo "- rotation stopped: $STOP"
    echo
    echo "## Seed-dependent"
    echo
    if [ "$dep" -gt 0 ]; then printf '%s\n' "${DEPLINES[@]}"; else echo "None."; fi
    echo
    echo "## No answer"
    echo
    if [ "$noans" -gt 0 ]; then printf '%s\n' "${NOLINES[@]}"; else echo "None."; fi
    echo
    echo "See docs/VERIFICATION.md, \"A check must not depend on the seed\"."
} > "$REPORT" || { echo "UNMEASURED: cannot write report" >&2; exit 2; }
echo "report: $REPORT"
exit 0
