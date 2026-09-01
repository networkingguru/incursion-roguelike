#!/bin/bash
# Hard invariant for inc-jcg4: non-normal detection must be byte-identical
# before and after the unified-light change.
#
# WHY THIS IS STRUCTURAL AS WELL AS BEHAVIORAL. inc-jcg4 edited only light-
# based reads: LightLevelAt/LightBrightAt/LightLitAt, BrightAt, the Vision.cpp
# Dist > LightRange*2 visual cutoff, and light-averse combat/message sites.
# Non-normal senses use separate InfraRange, BlindsightVisionPath, TremorRange
# and Perceives/PER_* paths; none was touched.  The Vision.cpp cutoff strips
# only PER_VISUAL/PER_SHADOW and became less aggressive, so it can only add
# visual cells and can never remove a non-visual detection.
#
# The required behavioral fixture is an orc with innate infravision inside a
# Deeper Darkness globe, carrying and equipping no light (LightRange == 0).
# Darkness makes normal-light vision contribute nothing, isolating the infra
# path.  For every fixed seed, this check compares the complete sequence of
# per-ShowMap visible/remembered/unseen counts written by INCURSION_MAP_PROBE;
# even a one-byte difference fails.  No deterministic first-level chargen in
# this repository grants player blindsight/tremorsense or scent, so this guard
# does not manufacture weaker proxy scenarios for them.
#
# The authoritative before side is 849b9b2, the last code commit before Phase
# 1; the after side defaults to HEAD.  Both are detached throwaway worktrees.
# Usage: tools/check_nonnormal_invariant.sh [after-ref]
# Exit: 0 byte-identical, 1 invariant changed, 2 build/run was inconclusive.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BEFORE_REF="849b9b2"
AFTER_REF="${1:-HEAD}"
SETUP_KEYS="$ROOT/tools/keys/nonnormal-infravision.keys"
RUN_KEYS="$ROOT/tools/keys/nonnormal-infravision-run.keys"
OPTIONS="$ROOT/tools/gates/Options.Dat"
SEEDS="1 2 3 4 5 6 7 8 9 10"
WORKROOT="$(mktemp -d "${TMPDIR:-/tmp}/inc-nonnormal.XXXXXX")" || exit 2
WORKTREES=""

cleanup() {
    for wt in $WORKTREES; do
        git worktree remove --force "$wt" >/dev/null 2>&1 || true
    done
    rm -rf "$WORKROOT"
    git worktree prune >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_side() { # run_side <label> <ref>
    local label="$1" ref="$2"
    local wt="$WORKROOT/$label"
    local seed out status run log dst rundir
    WORKTREES="$WORKTREES $wt"
    echo ">>> $label: checkout $ref"
    git worktree add --detach "$wt" "$ref" >/dev/null || return 2
    echo ">>> $label: build"
    (cd "$wt" && BACKEND=posix ./build_macos.sh) >/dev/null || return 2
    for seed in $SEEDS; do
        rundir="$WORKROOT/run-$label-$seed"
        out="$(cd "$wt" && INCURSION_RUN_DIR="$rundir" \
            INCURSION_OPTIONS="$OPTIONS" tools/headless.sh "$SETUP_KEYS" "$seed" 2>&1)"
        status=$?
        if [ "$status" -ne 0 ] || ! ls "$rundir"/save/* >/dev/null 2>&1; then
            echo "INCONCLUSIVE: $label seed $seed setup exited $status or wrote no save"
            echo "$out"
            return 2
        fi
        rm -f "$rundir/logs/mapprobe.log"
        out="$(cd "$wt" && INCURSION_RUN_DIR="$rundir" INCURSION_MAP_PROBE=1 \
            INCURSION_OPTIONS="$OPTIONS" tools/headless.sh "$RUN_KEYS" "$seed" 2>&1)"
        status=$?
        run="$rundir"
        log="$run/logs/mapprobe.log"
        if [ "$status" -ne 0 ] || [ ! -s "$log" ]; then
            echo "INCONCLUSIVE: $label seed $seed exited $status or wrote no mapprobe.log"
            echo "$out"
            return 2
        fi
        dst="$WORKROOT/$label-$seed.log"
        cp -f "$log" "$dst"
    done
}

run_side before "$BEFORE_REF" || exit 2
run_side after "$AFTER_REF" || exit 2

for seed in $SEEDS; do
    if ! cmp -s "$WORKROOT/before-$seed.log" "$WORKROOT/after-$seed.log"; then
        echo "FAIL: infravision mapprobe sequence differs on seed $seed"
        diff -u "$WORKROOT/before-$seed.log" "$WORKROOT/after-$seed.log" || true
        exit 1
    fi
done

echo "PASS: infravision in darkness is byte-identical across $BEFORE_REF..$AFTER_REF ($SEEDS)."
exit 0
