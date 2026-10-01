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
#        tools/check_distant_light_vision.sh --selftest
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

# inc-fxhl: an EXIT trap can only walk state the PARENT shell owns. run_side
# runs inside "$( )", so a parent array append lands in the subshell's copy and
# dies with it, and the trap removes nothing. The register is a file so the
# write survives the subshell; cleanup reads it in the parent.
REGISTER="$(mktemp "${TMPDIR:-/tmp}/distlight-wt.XXXXXX")" || exit 2
register_worktree() { printf '%s\n' "$1" >> "$REGISTER"; }

remove_worktree() { # remove_worktree <path>
    git worktree remove --force "$1" 2>/dev/null || rm -rf "$1"
}

cleanup() {
    local wt
    [ -f "$REGISTER" ] || { git worktree prune 2>/dev/null || true; return 0; }
    while IFS= read -r wt; do
        [ -n "$wt" ] || continue
        remove_worktree "$wt"
    done < "$REGISTER"
    rm -f "$REGISTER"
    git worktree prune 2>/dev/null || true
}
on_exit()      { cleanup; }
on_interrupt() { cleanup; exit 130; }
on_terminate() { cleanup; exit 143; }
trap on_exit EXIT
trap on_interrupt INT
trap on_terminate TERM

selftest() {
    local wt="/tmp/distlight-selftest.$$" seen="$REGISTER.seen"
    local rc=0
    remove_worktree() { printf '%s\n' "$1" >> "$seen"; }
    ( register_worktree "$wt" )   # the "$( )"-shaped subshell this script uses
    cleanup
    if grep -qxF "$wt" "$seen"; then
        echo "selftest: PASS register reached the trap ($wt)"
    else
        echo "selftest: FAIL register did not reach the trap; trap saw '$(cat "$seen" 2>/dev/null)'"
        rc=1
    fi
    rm -f "$seen"
    return $rc
}
[ "${1:-}" = "--selftest" ] && { selftest; exit $?; }

BEFORE_REF="$(git rev-parse --verify "${FIX}^" 2>/dev/null)" || {
    echo "INCONCLUSIVE: ${FIX}^ does not resolve -- pass the fix commit"; exit 2; }
AFTER_REF="$(git rev-parse --verify "$FIX" 2>/dev/null)" || {
    echo "INCONCLUSIVE: $FIX does not resolve"; exit 2; }

sum_visible() { # sum_visible <mapprobe.log> -> integer
    awk '{for(i=1;i<=NF;i++) if($i ~ /^visible=/){sub("visible=","",$i); s+=$i}}
         END{print s+0}' "$1"
}

# Build <ref> in a detached worktree, run dive on every seed, echo one
# "<seed> <visible-total>" line per seed on stdout. All noise goes to stderr.
run_side() { # run_side <label> <ref>
    local label="$1" ref="$2"
    local wt="$ROOT/.wt-distlight-$label.$$"
    register_worktree "$wt"
    echo ">>> $label: checkout $ref" >&2
    git worktree add --detach "$wt" "$ref" >&2 || return 2
    echo ">>> $label: build" >&2
    ( cd "$wt" && BACKEND=posix ./build_macos.sh ) >&2 || return 2
    local s out run log dest
    for s in $SEEDS; do
        out="$( cd "$wt" && INCURSION_MAP_PROBE=1 INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh "$KEYS_ABS" "$s" 2>&1 )"
        run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
        if [ -z "$run" ]; then
            # The worktree is about to be removed, so the run dir (or, with no
            # run dir, headless.sh's captured output) is copied to git-ignored
            # $ROOT/logs/; print THAT surviving path.
            dest="$ROOT/logs/distlight-$label-seed$s.$$"
            mkdir -p "$dest" || return 2
            printf '%s\n' "$out" > "$dest/headless.out"
            echo "INCONCLUSIVE: $label seed $s produced no run dir -- headless.sh failed; its output was saved to $dest/headless.out" >&2
            printf '%s\n' "$out" >&2
            return 2
        fi
        log="$run/logs/mapprobe.log"
        [ -f "$log" ] || {
            dest="$ROOT/logs/distlight-$label-seed$s.$$"
            mkdir -p "$dest" || return 2
            cp -f "$run"/* "$dest"/ 2>/dev/null || cp -rf "$run"/. "$dest"/ 2>/dev/null
            if git grep -q INCURSION_MAP_PROBE "$ref" -- src 2>/dev/null; then
                echo "INCONCLUSIVE: no mapprobe.log for $label seed $s: $ref carries the probe, so the run failed: $dest" >&2
            else
                echo "INCONCLUSIVE: no mapprobe.log for $label seed $s: $ref does not carry the probe; the run dir was saved to $dest" >&2
            fi
            return 2; }
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
