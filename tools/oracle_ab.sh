#!/bin/bash
# Produce a before/after gameplay oracle for a single fix, by building the game
# on both sides of the fix commit and running the SAME key script on each.
#
#   tools/oracle_ab.sh <fix-commit> <keys-file> <seed> <dump-label>
#   tools/oracle_ab.sh e47f209 tools/keys/sunblade-light.keys 1 map-after-activation
#
# WHY THIS EXISTS. REPORTING-GATE's Observed tier needs the game watched behaving
# differently either side of a fix, with a number read off a player-facing screen
# on each side (docs/REPORTING-GATE.md, bd inc-cyma). A grep that proves the
# source changed is only Traced. This script gives every fix that is its own
# commit a real A/B run for free, and it never touches the working tree: it
# checks out <fix-commit> and <fix-commit>^ into throwaway detached worktrees,
# builds each, runs the keys, and copies out the one dump the label names.
#
# THE "BEFORE" IS AUTHORITATIVE HISTORY, not a hand-written revert. That is the
# whole point of keying on the commit: the without-fix state is exactly what the
# repository recorded before the fix, so it cannot drift.
#
# The keys file is read by its given path, so it need not exist inside either
# worktree; its @include lines resolve against its own directory (tools/keys/),
# whose contents -- chargen.keys and friends -- are stable across the two commits.
#
# The two dumps land under docs/evidence/<keys-basename>/, which is untracked by
# policy (feedback: evidence stays untracked until a PR needs it). Read the
# number off them with the item's own check script; this runner only produces
# the comparable pair and prints the player row of each for a quick look.
#
# Exit: 0 both builds ran and both dumps were produced; non-zero otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FIX="${1:?usage: oracle_ab.sh <fix-commit> <keys-file> <seed> <dump-label>}"
KEYS="${2:?keys file required}"
SEED="${3:?seed required}"
LABEL="${4:?dump label required}"

[ -f "$KEYS" ] || { echo "no such keys file: $KEYS" >&2; exit 2; }
KEYS_ABS="$(cd "$(dirname "$KEYS")" && pwd)/$(basename "$KEYS")"
BEFORE_REF="$(git rev-parse --verify "${FIX}^")"
AFTER_REF="$(git rev-parse --verify "$FIX")"

EVID="$ROOT/docs/evidence/$(basename "$KEYS" .keys)"
mkdir -p "$EVID"

WORKTREES=()
cleanup() {
    for wt in "${WORKTREES[@]:-}"; do
        [ -n "$wt" ] || continue
        git worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    done
    git worktree prune 2>/dev/null || true
}
trap cleanup EXIT

# Build <ref> in a detached worktree, run the keys, copy out the labelled dump.
# Echoes the path of the copied dump on stdout; all progress goes to stderr.
run_side() {
    local side="$1" ref="$2"
    local wt run screens dump out
    wt="$(mktemp -d "${TMPDIR:-/tmp}/oracle-ab-${side}.XXXXXX")"
    WORKTREES+=("$wt")

    echo ">>> $side: checkout $ref into $wt" >&2
    git worktree add --detach "$wt" "$ref" >&2

    echo ">>> $side: build" >&2
    ( cd "$wt" && BACKEND=posix ./build_macos.sh ) >&2

    run="$wt/logs/runs/${side}-run"
    echo ">>> $side: run $KEYS_ABS (seed $SEED)" >&2
    ( cd "$wt" && INCURSION_RUN_DIR="$run" tools/headless.sh "$KEYS_ABS" "$SEED" ) >&2

    screens="$run/logs/screens"
    dump="$(ls "$screens"/*"$LABEL"*.txt 2>/dev/null | head -1 || true)"
    [ -n "$dump" ] || { echo "$side: no dump matched label '$LABEL' in $screens" >&2; return 1; }

    out="$EVID/${side}-${LABEL}.txt"
    cp "$dump" "$out"
    echo "$out"
}

BEFORE_DUMP="$(run_side before "$BEFORE_REF")"
AFTER_DUMP="$(run_side after "$AFTER_REF")"

echo
echo "=== oracle A/B: $(basename "$KEYS") @ $FIX (seed $SEED, label '$LABEL') ==="
echo "before ($BEFORE_REF): $BEFORE_DUMP"
echo "after  ($AFTER_REF): $AFTER_DUMP"
echo
echo "--- before: the player row ---"
grep -n '@' "$BEFORE_DUMP" || true
echo "--- after: the player row ---"
grep -n '@' "$AFTER_DUMP" || true
