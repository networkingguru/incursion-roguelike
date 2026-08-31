#!/bin/bash
# Does a self-luminous cell within sight range, but past the player's own
# light/shadow range, become visible? (bd inc-qw4d.)
#
# THE DEFECT. Map::MarkAsSeen (src/Vision.cpp) returned true -- "stop this
# vision ray" -- at the first unlit cell past shadow range. A distant torch
# sits behind such cells, so no ray ever reached it and it was never marked
# VI_VISIBLE, even though the level-wide light map (src/Light.cpp, LightLitAt)
# already knew the cell was lit. The fix lets the ray walk on through an unlit
# cell, leaving it unmarked, so a lit cell farther out is still reached; real
# occluders (opaque terrain, magical Dark, obscuring) still end the ray in
# CARE_ABOUT_SEEING, which the fix does not touch.
#
# HOW THIS PROVES IT. The fix can only ADD visible cells (a lit cell the ray
# now reaches), never remove one. So across a set of seeds the after-build's
# summed `visible=` count from INCURSION_MAP_PROBE must be >= the before-build's
# on every seed, and strictly greater on at least one. A build that reveals the
# distant light passes; the unfixed build cannot, because its rays die first.
#
# It keys on the fix commit and builds both sides in throwaway worktrees, the
# same mechanism as tools/oracle_ab.sh, so the "before" is authoritative history
# and cannot drift. Pass the commit that carries the fix; it defaults to HEAD.
#
# Usage: tools/check_distant_light_vision.sh [fix-commit]
# Exit:  0 pass, 1 fail (no gain, or the fix reduced visibility somewhere),
#        2 inconclusive (a build or a run did not produce a probe log).
#
# Needs git worktree support and the headless build toolchain.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

FIX="${1:-HEAD}"
KEYS="tools/keys/dive.keys"
KEYS_ABS="$ROOT/$KEYS"
SEEDS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20"

BEFORE_REF="$(git rev-parse --verify "${FIX}^" 2>/dev/null)" || {
    echo "INCONCLUSIVE: ${FIX}^ does not resolve -- pass the fix commit"; exit 2; }
AFTER_REF="$(git rev-parse --verify "$FIX" 2>/dev/null)" || {
    echo "INCONCLUSIVE: $FIX does not resolve"; exit 2; }

WORKTREES=()
cleanup() {
    for wt in "${WORKTREES[@]:-}"; do
        [ -n "$wt" ] || continue
        git worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    done
    git worktree prune 2>/dev/null || true
}
trap cleanup EXIT

sum_visible() { # sum_visible <mapprobe.log> -> integer
    awk '{for(i=1;i<=NF;i++) if($i ~ /^visible=/){sub("visible=","",$i); s+=$i}}
         END{print s+0}' "$1"
}

# Build <ref> in a detached worktree, run dive on every seed, echo one
# "<seed> <visible-total>" line per seed on stdout. All noise goes to stderr.
run_side() { # run_side <label> <ref>
    local label="$1" ref="$2"
    local wt="$ROOT/.wt-distlight-$label.$$"
    WORKTREES+=("$wt")
    echo ">>> $label: checkout $ref" >&2
    git worktree add --detach "$wt" "$ref" >&2 || return 2
    echo ">>> $label: build" >&2
    ( cd "$wt" && BACKEND=posix ./build_macos.sh ) >&2 || return 2
    local s out run log
    for s in $SEEDS; do
        out="$( cd "$wt" && INCURSION_MAP_PROBE=1 tools/headless.sh "$KEYS_ABS" "$s" 2>&1 )"
        run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
        log="$run/logs/mapprobe.log"
        [ -f "$log" ] || { echo "INCONCLUSIVE: no mapprobe.log for $label seed $s" >&2; return 2; }
        echo "$s $(sum_visible "$log")"
    done
}

BEFORE="$(run_side before "$BEFORE_REF")" || { echo "INCONCLUSIVE: before side failed"; exit 2; }
AFTER="$(run_side after  "$AFTER_REF")"  || { echo "INCONCLUSIVE: after side failed"; exit 2; }

# Compare seed by seed. after must never be below before; it must exceed it once.
FAIL=0
GAINS=0
printf '%-6s %10s %10s %8s\n' seed before after delta
while read -r s b; do
    a="$(printf '%s\n' "$AFTER" | awk -v s="$s" '$1==s{print $2}')"
    [ -n "$a" ] || { echo "INCONCLUSIVE: after has no seed $s"; exit 2; }
    d=$((a - b))
    printf '%-6s %10s %10s %8s\n' "$s" "$b" "$a" "$d"
    if [ "$d" -lt 0 ]; then
        echo "  ^ FAIL: the fix HID cells on seed $s -- it must only reveal"
        FAIL=1
    elif [ "$d" -gt 0 ]; then
        GAINS=$((GAINS + 1))
    fi
done <<< "$BEFORE"

echo
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: visibility fell on at least one seed; the fix is not purely additive."
    exit 1
fi
if [ "$GAINS" -eq 0 ]; then
    echo "FAIL: no seed revealed any extra cell, so this build does not carry the fix."
    exit 1
fi
echo "PASS: $GAINS of $(printf '%s\n' "$BEFORE" | grep -c .) seeds reveal distant light, none hide any."
exit 0
