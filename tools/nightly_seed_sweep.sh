#!/usr/bin/env bash
# gate: none <why: it sweeps other checks for up to four hours; the 23:00 launchd job calls it>
#
# Sweep the live/smoke checks over other seeds, on idle-machine time. (inc-ug5y, inc-jt3yu)
#   tools/nightly_seed_sweep.sh [--budget SECONDS] [--lanes N] [--state FILE]
#                               [--pending FILE] [--report FILE]
# The launchd job com.brianhill.incursion.seed-sweep runs it at 23:00 with a 4 h budget.
# It builds its own detached worktrees of master under $NIGHTLY_SWEEP_BASE (default
# $TMPDIR/incursion-seed-sweep): per lane one root plus 5 slots. A lane sweeps one check
# at a time (control run, then 5 seeds at once). Lanes default to ncpu/5, minimum 1.
# The budget counts from the end of the setup builds; no check starts after it ends.
# A live/smoke check changed on master since the last run goes first (pending file);
# the others rotate after the state file's last_check. State is key=value lines
# (last_check, last_commit); an old one-line file holding a check name still reads.
# Report only: exit 0 whenever it ran, 2 when it cannot measure.
# Test-only overrides: NIGHTLY_SWEEP_CHECK_DIR, NIGHTLY_SWEEP_CMD, NIGHTLY_SWEEP_LOAD_GUARD,
# NIGHTLY_SWEEP_BUILD_CMD, NIGHTLY_SWEEP_BASE.
# See docs/VERIFICATION.md, "A check must not depend on the seed".

cd "$(dirname "$0")/.." || exit 2
ROOT="$PWD"
BUDGET=14400
LANES=""
STATE="logs/seed-sweep/rotation.state"
PENDING="logs/seed-sweep/pending.txt"
DATE="$(date +%Y-%m-%d)"
REPORT="logs/seed-sweep/nightly-$DATE.md"
BUILD_CMD="${NIGHTLY_SWEEP_BUILD_CMD:-BACKEND=posix ./build_macos.sh}"
GUARD="${NIGHTLY_SWEEP_LOAD_GUARD:-$ROOT/tools/load_guard.sh}"

usage() { echo "usage: tools/nightly_seed_sweep.sh [--budget SECONDS] [--lanes N] [--state FILE] [--pending FILE] [--report FILE]" >&2; exit 2; }
while [ $# -gt 0 ]; do
    case "$1" in
        --budget) [ $# -ge 2 ] || usage; BUDGET="$2"; shift 2 ;;
        --lanes) [ $# -ge 2 ] || usage; LANES="$2"; shift 2 ;;
        --state) [ $# -ge 2 ] || usage; STATE="$2"; shift 2 ;;
        --pending) [ $# -ge 2 ] || usage; PENDING="$2"; shift 2 ;;
        --report) [ $# -ge 2 ] || usage; REPORT="$2"; shift 2 ;;
        *) usage ;;
    esac
done
case "$BUDGET" in ''|*[!0-9]*) usage ;; esac
if [ -z "$LANES" ]; then
    ncpu="$(sysctl -n hw.ncpu 2>/dev/null)"; case "$ncpu" in ''|*[!0-9]*) ncpu=5 ;; esac
    LANES=$(( ncpu / 5 ))
fi
case "$LANES" in ''|*[!0-9]*) usage ;; esac
[ "$LANES" -ge 1 ] || LANES=1

if [ -n "${NIGHTLY_SWEEP_CMD:-}" ] && [ ! -x "$NIGHTLY_SWEEP_CMD" ]; then
    echo "UNMEASURED: sweep command missing: $NIGHTLY_SWEEP_CMD" >&2; exit 2
fi

WORK="$(mktemp -d)" || exit 2
CREATED=()
BPIDS=()
LANEPIDS=()
SWEEP_BASE="${NIGHTLY_SWEEP_BASE:-${TMPDIR:-/tmp}/incursion-seed-sweep}"
mkdir -p "$SWEEP_BASE" && SWEEP_BASE="$(cd "$SWEEP_BASE" && pwd -P)" || { echo "UNMEASURED: cannot create $SWEEP_BASE" >&2; exit 2; }
[ -n "$SWEEP_BASE" ] && [ "$SWEEP_BASE" != "/" ] || { echo "UNMEASURED: bad sweep base" >&2; exit 2; }

cleanup() {
    trap - EXIT INT TERM
    local p d
    for p in "${LANEPIDS[@]}"; do kill "$p" 2>/dev/null; done
    # Only trees this run created: delete each directory, then one prune drops their records.
    for d in "${CREATED[@]}"; do [ -n "$d" ] && rm -rf "$d"; done
    git -C "$ROOT" worktree prune > /dev/null 2>&1
    for d in "$SWEEP_BASE"/lane*; do [ -d "$d" ] && rm -rf "$d"; done
    rmdir "$SWEEP_BASE" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$(dirname "$STATE")" "$(dirname "$PENDING")" "$(dirname "$REPORT")" \
    || { echo "UNMEASURED: cannot create output directories" >&2; exit 2; }
: > "$REPORT" || { echo "UNMEASURED: cannot write report" >&2; exit 2; }

unmeasured() { # unmeasured <reason>
    { echo "# Nightly seed sweep $DATE"; echo; echo "UNMEASURED: $1"; } > "$REPORT"
    echo "UNMEASURED: $1" >&2
    exit 2
}

# Remove worktrees an earlier run left under the sweep base. Nothing outside it.
git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r p; do
    case "$p" in "$SWEEP_BASE"/*) git -C "$ROOT" worktree remove --force "$p" > /dev/null 2>&1 ;; esac
done
git -C "$ROOT" worktree prune
for d in "$SWEEP_BASE"/lane*; do [ -d "$d" ] && rm -rf "$d"; done

HEADSHA="$(git -C "$ROOT" rev-parse master 2>/dev/null)" || unmeasured "cannot resolve master"

# Make one lane's six trees, one after the other (concurrent "git worktree add" calls
# race on git's worktree records). Each build starts in the background at once.
mklane() { # mklane <n>
    local l="$1" d s
    for s in 0 1 2 3 4 5; do
        if [ "$s" -eq 0 ]; then d="$SWEEP_BASE/lane$l/root$l"; else d="$SWEEP_BASE/lane$l/slot$l-$s"; fi
        CREATED+=("$d")
        git -C "$ROOT" worktree add -q --detach "$d" "$HEADSHA" > "$WORK/wt.out" 2>&1 \
            || unmeasured "cannot create worktree $d: $(tail -1 "$WORK/wt.out")"
        mkdir -p "$d/logs"
        ( cd "$d" && bash -c "$BUILD_CMD" ) > "$d/logs/sweep-setup-build.txt" 2>&1 &
        BPIDS+=("$!")
    done
}

mklane 1
CHECK_DIR="${NIGHTLY_SWEEP_CHECK_DIR:-$SWEEP_BASE/lane1/root1/tools}"

CANDS=()
while IFS= read -r f; do
    if head -40 "$f" | grep -qxE '# gate: (live|smoke)'; then CANDS+=("$(basename "$f")"); fi
done < <(find "$CHECK_DIR" -maxdepth 1 -name 'check_*.sh' | LC_ALL=C sort)
N=${#CANDS[@]}
[ "$N" -gt 0 ] || unmeasured "no live/smoke checks in $CHECK_DIR"
printf '%s\n' "${CANDS[@]}" > "$WORK/cands"

# State: key=value lines; an old one-line file holding a bare check name is last_check.
LAST_CHECK=""; LAST_COMMIT=""
if [ -s "$STATE" ]; then
    if [ "$(grep -c . "$STATE")" -eq 1 ] && ! grep -q '=' "$STATE"; then
        LAST_CHECK="$(head -1 "$STATE")"
    else
        LAST_CHECK="$(sed -n 's/^last_check=//p' "$STATE" | head -1)"
        LAST_COMMIT="$(sed -n 's/^last_commit=//p' "$STATE" | head -1)"
    fi
fi
printf '%s' "$LAST_CHECK" > "$WORK/last_check"
printf '%s' "$LAST_COMMIT" > "$WORK/last_commit"
write_state() {
    printf 'last_check=%s\nlast_commit=%s\n' "$(cat "$WORK/last_check")" "$(cat "$WORK/last_commit")" > "$STATE"
}

# changed = live/smoke checks touched on master since last_commit.
: > "$WORK/changed"
if [ -n "$LAST_COMMIT" ] && git -C "$ROOT" cat-file -e "$LAST_COMMIT^{commit}" 2>/dev/null; then
    git -C "$ROOT" diff --name-only --diff-filter=d "$LAST_COMMIT" "$HEADSHA" -- 'tools/check_*.sh' \
        | while IFS= read -r f; do basename "$f"; done | grep -xFf "$WORK/cands" > "$WORK/changed"
fi
# pending = (old pending U changed) ^ candidates, sorted.
{ cat "$PENDING" 2>/dev/null; cat "$WORK/changed"; } | grep . | grep -xFf "$WORK/cands" | LC_ALL=C sort -u > "$WORK/pending"
cp "$WORK/pending" "$WORK/pending.start"
cp "$WORK/pending" "$PENDING" || unmeasured "cannot write pending file"

# queue = pending first, then the rotation after last_check (wrap), skipping pending names.
QNAME=(); QKIND=()
while IFS= read -r c; do QNAME+=("$c"); QKIND+=(p); done < "$WORK/pending"
START=0
for i in "${!CANDS[@]}"; do
    [ "${CANDS[$i]}" = "$LAST_CHECK" ] && START=$(( (i + 1) % N ))
done
for ((k = 0; k < N; k++)); do
    c="${CANDS[$(( (START + k) % N ))]}"
    grep -qxF "$c" "$WORK/pending" && continue
    QNAME+=("$c"); QKIND+=(r)
done
QN=${#QNAME[@]}
[ "$LANES" -le "$QN" ] || LANES="$QN"
for ((l = 2; l <= LANES; l++)); do mklane "$l"; done

# Wait for the setup builds started in mktree.
i=0
for d in "${CREATED[@]}"; do
    wait "${BPIDS[$i]}" || BADTREE="$d"
    i=$((i + 1))
done
[ -z "${BADTREE:-}" ] || unmeasured "setup build failed in $BADTREE, log: $BADTREE/logs/sweep-setup-build.txt"

if [ -z "${NIGHTLY_SWEEP_CMD:-}" ]; then
    [ -x "$SWEEP_BASE/lane1/root1/tools/seed_sweep.sh" ] || unmeasured "sweep command missing in lane 1 root"
fi

OUTDIR="$(dirname "$REPORT")/nightly-$DATE"
mkdir -p "$OUTDIR" || unmeasured "cannot create $OUTDIR"
write_state || unmeasured "cannot write state"

echo 0 > "$WORK/counter"
LOCK="$WORK/lock"
T0="$(date +%s)"
over_budget() { [ $(( $(date +%s) - T0 )) -gt "$BUDGET" ]; }
lock() { until mkdir "$LOCK" 2>/dev/null; do sleep 0.2; done; }
unlock() { rmdir "$LOCK"; }

take() { # prints the next queue index, or nothing when the queue is empty
    local idx
    lock
    idx="$(cat "$WORK/counter")"
    if [ "$idx" -lt "$QN" ]; then
        echo $((idx + 1)) > "$WORK/counter"
        [ "${QKIND[$idx]}" = r ] && { printf '%s' "${QNAME[$idx]}" > "$WORK/last_check"; write_state; }
        echo "$idx"
    fi
    unlock
}

lane() { # lane <n>
    local l="$1" root slots s idx c rc last cmd
    root="$SWEEP_BASE/lane$l/root$l"
    slots=""; for s in 1 2 3 4 5; do slots="$slots $SWEEP_BASE/lane$l/slot$l-$s"; done
    slots="${slots# }"
    cmd="${NIGHTLY_SWEEP_CMD:-$root/tools/seed_sweep.sh}"
    while :; do
        until "$GUARD" > /dev/null 2>&1; do
            over_budget && return
            sleep 30
        done
        over_budget && return
        idx="$(take)"
        [ -n "$idx" ] || return
        c="${QNAME[$idx]}"
        ( cd "$root" && "$cmd" --slots "$slots" "tools/$c" ) > "$OUTDIR/$c.txt" 2>&1
        rc=$?
        mkdir -p "$OUTDIR/$c.d"; mv "$root"/logs/seed-sweep/* "$OUTDIR/$c.d/" 2>/dev/null
        last="$(grep . "$OUTDIR/$c.txt" | tail -1 | cut -c1-200)"
        printf '%s\t%s\t%s\n' "$c" "$rc" "$last" >> "$WORK/results.$l"
        lock
        grep -vxF "$c" "$WORK/pending" > "$WORK/pending.new"
        mv "$WORK/pending.new" "$WORK/pending"
        cp "$WORK/pending" "$PENDING"
        unlock
    done
}

for ((l = 1; l <= LANES; l++)); do
    lane "$l" &
    LANEPIDS+=("$!")
done
for p in "${LANEPIDS[@]}"; do wait "$p"; done
LANEPIDS=()

printf '%s' "$HEADSHA" > "$WORK/last_commit"
write_state || unmeasured "cannot write state"

# Verdicts, from the per-lane result files.
cat "$WORK"/results.* 2>/dev/null > "$WORK/results.all"
swept=$(grep -c . "$WORK/results.all")
indep=0; notdriven=0; dep=0; noans=0
DEPLINES=(); NOLINES=()
while IFS="$(printf '\t')" read -r c rc last; do
    [ -n "$c" ] || continue
    case "$rc" in
        0) if grep -q 'NOT SEED-DRIVEN' "$OUTDIR/$c.txt"; then notdriven=$((notdriven + 1)); else indep=$((indep + 1)); fi ;;
        1) dep=$((dep + 1)); DEPLINES+=("- \`$c\`: $last") ;;
        *) noans=$((noans + 1)); NOLINES+=("- \`$c\`: exit $rc") ;;
    esac
done < "$WORK/results.all"
done_n=$(cat "$WORK/counter")
if [ "$done_n" -ge "$QN" ]; then STOP="queue finished ($QN checks)"; else STOP="budget spent after ${BUDGET}s; $((QN - done_n)) of $QN queued checks not started"; fi

{
    echo "# Nightly seed sweep $DATE"
    echo
    echo "- swept: $swept"
    echo "- lanes: $LANES"
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
    echo "## Changed since last sweep"
    echo
    if [ -s "$WORK/pending.start" ]; then
        while IFS= read -r c; do
            v="$(awk -F'\t' -v c="$c" '$1 == c { print "exit " $2 ": " $3 }' "$WORK/results.all")"
            echo "- \`$c\`: ${v:-not reached}"
        done < "$WORK/pending.start"
    else
        echo "None."
    fi
    echo
    echo "## Carried to next run"
    echo
    if [ -s "$WORK/pending" ]; then sed 's/.*/- `&`/' "$WORK/pending"; else echo "None."; fi
    echo
    echo "See docs/VERIFICATION.md, \"A check must not depend on the seed\"."
} > "$REPORT" || unmeasured "cannot write report"
echo "report: $REPORT"
exit 0
