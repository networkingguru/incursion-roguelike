#!/usr/bin/env bash
#
# The gate an unattended run's branch must clear before it reaches master.
#
#   tools/nightly_verify.sh --record    # before the run: what already failed
#   tools/nightly_verify.sh --compare   # after the run: did this run break any
#   tools/nightly_verify.sh             # same as --compare, no recorded base
#
# Exit: 0 safe to merge
#       1 this run broke something, or a build failed
#       2 could not measure
#
# WHY A RATCHET AND NOT "EVERYTHING MUST PASS". tools/check_probe_hooks.sh exits
# 1 on master today and will keep doing so until Brian names the bead that
# INCURSION_STAIR_WARN_PROBE serves (bd inc-loa.12) -- a question the run is
# forbidden to guess at. A gate that demanded a clean sweep would block every
# merge on a question only he can answer, which is the opposite of the point.
# So the rule is: a check that ALREADY failed before the run is not this run's
# fault; a check that passed before and fails after is, and it stops the merge.
#
# The BUILDS are absolute, not ratcheted. A tree that does not compile is never
# safe to merge, whatever it did yesterday. Both backends build, because they
# are separate main()s and a change can break one while the other compiles.
#
# WHERE THE BASE IS RECORDED. $NIGHTLY_VERIFY_STATE if set (the harness points it
# outside the repository), otherwise logs/nightly-verify-base.txt. It is a
# record of a run, not source: never commit it.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

STATE="${NIGHTLY_VERIFY_STATE:-$ROOT/logs/nightly-verify-base.txt}"
BASE_REF="${NIGHTLY_BASE_REF:-master}"
MODE="compare"

SKIP_BUILDS=0
case "${1:-}" in
    --record)      MODE="record" ;;
    --compare)     MODE="compare" ;;
    # --checks-only exists so the ratchet can be exercised without rebuilding.
    # A build here overwrites ./incursion and mod/Incursion.Mod, which is not
    # safe to do while somebody is playing the game out of this directory.
    --checks-only) MODE="compare"; SKIP_BUILDS=1 ;;
    "")            MODE="compare" ;;
    -h|--help)     sed -n '2,10p' "$0"; exit 0 ;;
    *)             echo "unknown argument: $1" >&2; exit 2 ;;
esac

# The ratcheted checks, in the order a reader wants them. Each is cheap -- all
# of them together are seconds, so running them twice a night costs nothing.
# A check added here MUST be deterministic and MUST NOT need a build.
RATCHET_CHECKS=(
    "tools/check_upstream_marks.sh"
    "tools/check_probe_hooks.sh"
    "tools/check_format_strings.sh"
    "tools/check_citations.sh --selftest"
    "tools/check_doc_citations.sh --base $BASE_REF"
    "tools/check_comment_budget.sh"
    "tools/check_readme_checks.sh"
    "tools/check_commit_lane.sh"
)

run_check() { # run_check "<command line>" -> echoes the exit code
    local cmd="$1"
    ( eval "$cmd" ) > /dev/null 2>&1
    echo $?
}

# ------------------------------------------------------------------ record ---
if [ "$MODE" = "record" ]; then
    mkdir -p "$(dirname "$STATE")" || exit 2
    : > "$STATE"
    for c in "${RATCHET_CHECKS[@]}"; do
        rc="$(run_check "$c")"
        printf '%s\t%s\n' "$rc" "$c" >> "$STATE"
        printf 'base %-3s %s\n' "$rc" "$c"
    done
    echo "recorded the pre-run state in $STATE"
    exit 0
fi

# ----------------------------------------------------------------- compare ---
FAILED=0

if [ "$SKIP_BUILDS" = 1 ]; then
    echo "--- builds SKIPPED (--checks-only) ---"
else
    echo "--- builds (absolute: a tree that does not compile never merges) ---"
    for build in "BACKEND=posix ./build_macos.sh" "./build_macos.sh"; do
        printf '%s ... ' "$build"
        if ( eval "$build" ) > /dev/null 2>&1; then
            echo "ok"
        else
            echo "FAILED"
            echo "    re-run it to see why: $build"
            FAILED=1
        fi
    done
fi

echo
echo "--- checks (ratcheted against the state before the run) ---"
if [ -r "$STATE" ]; then
    echo "base recorded in $STATE"
else
    echo "NO recorded base. Every check must pass outright."
fi

for c in "${RATCHET_CHECKS[@]}"; do
    now="$(run_check "$c")"
    was=""
    if [ -r "$STATE" ]; then
        was="$(awk -F'\t' -v c="$c" '$2 == c { print $1 }' "$STATE" | head -1)"
    fi
    [ -n "$was" ] || was=0
    if [ "$now" = "0" ]; then
        if [ "$was" != "0" ]; then
            printf 'FIXED       %s (was exit %s)\n' "$c" "$was"
        else
            printf 'ok          %s\n' "$c"
        fi
    elif [ "$was" != "0" ]; then
        printf 'pre-existing %s (exit %s before and after -- not this run)\n' "$c" "$now"
    else
        printf 'BROKEN      %s (exit %s; it passed before this run)\n' "$c" "$now"
        FAILED=1
    fi
done

echo
if [ "$FAILED" = 0 ]; then
    echo "=== PASS: safe to merge ==="
    exit 0
fi
echo "=== FAIL: do NOT merge. The branch stays for a person to read. ==="
exit 1
