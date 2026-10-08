#!/usr/bin/env bash
#
# fast_checks.sh -- run the FAST set: the checks that are safe to run on every
# commit, in seconds, before the landing gate.
#
# WHY THIS EXISTS. Some repository-hygiene checks cost 2-4 seconds each and
# only run inside the 4-minute cheap tier of the landing gate. This runner
# gives them a separate set that finishes in seconds, so a commit gets fast
# feedback. It is called by .beads/hooks/pre-commit (from bead worktrees only)
# and by tools/finish_bead.sh before the gate (bead inc-3s7w).
#
# A CHECK JOINS THE FAST SET with one comment line in its first 40 lines:
#   # gate-fast: <reason>
# mirroring `# gate-serial: <reason>`. The reason MUST be non-empty. This
# marker does NOT change the check's own `# gate:` tier.
#
# THE LIMIT. Each check gets FAST_LIMIT seconds (env INCURSION_FAST_LIMIT,
# default 15). A check still running at the limit is killed and counted as a
# failure: it is too slow for a set that promises seconds.
#
# Usage: tools/fast_checks.sh [--dir <path>] [--help]
#
# Exit: 0 every fast check passed (a check exiting 2 is UNMEASURED, not a fail)
#       1 at least one fast check failed or timed out
#       2 no fast check was found (a missing set is not a pass)
#
set -uo pipefail

LIMIT="${INCURSION_FAST_LIMIT:-15}"
CHECK_DIR=""
DIR_GIVEN=0

usage() { sed -n '2,26p' "$0"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)
            [ $# -ge 2 ] || { echo "--dir needs a path" >&2; exit 2; }
            CHECK_DIR="$2"; DIR_GIVEN=1; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

case "$LIMIT" in
    ''|*[!0-9]*) echo "INCURSION_FAST_LIMIT must be a positive integer, got '$LIMIT'" >&2; exit 2 ;;
esac
[ "$LIMIT" -gt 0 ] || { echo "INCURSION_FAST_LIMIT must be positive" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "COULD NOT MEASURE: not in a git repository" >&2; exit 2; }
cd "$ROOT" || exit 2

if [ "$DIR_GIVEN" = 0 ]; then
    CHECK_DIR="$ROOT/tools"
fi
[ -d "$CHECK_DIR" ] || { echo "no such directory: $CHECK_DIR" >&2; exit 2; }

# A fast check carries a non-empty '# gate-fast: <reason>' in its first 40
# lines. Same shape as nightly_verify.sh's is_serial_file.
is_fast_file() { # <check file>
    grep -Eq '^#[[:space:]]*gate-fast:[[:space:]]*[^[:space:]]' \
        <<<"$(sed -n '1,40p' "$1")"
}

CHECKS=()
for f in "$CHECK_DIR"/check_*.sh "$CHECK_DIR"/check_*.py; do
    [ -f "$f" ] || continue
    is_fast_file "$f" && CHECKS+=( "$f" )
done

if [ "${#CHECKS[@]}" -eq 0 ]; then
    echo "no fast checks found in $CHECK_DIR (nothing to run is not a pass)" >&2
    exit 2
fi

command -v perl >/dev/null 2>&1 || {
    echo "COULD NOT MEASURE: perl is needed to enforce the time limit" >&2
    exit 2
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fast_checks.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

# Launch every check in parallel. Each is wrapped in perl's alarm so a check
# that overruns is killed even though macOS ships no timeout(1); alarm
# survives the exec into the check. The wrapper records the exit code so the
# report can be printed in a stable order once every job is done.
PIDS=()
for i in "${!CHECKS[@]}"; do
    out="$TMP/$i.out"
    st="$TMP/$i.exit"
    start="$TMP/$i.start"
    end="$TMP/$i.end"
    date +%s > "$start"
    (
        perl -e 'alarm shift; exec @ARGV' "$LIMIT" "${CHECKS[$i]}" > "$out" 2>&1
        echo $? > "$st"
        date +%s > "$end"
    ) &
    PIDS+=( "$!" )
done

for p in "${PIDS[@]}"; do
    wait "$p"
done

# Report in discovery order.
failed=0
for i in "${!CHECKS[@]}"; do
    f="${CHECKS[$i]}"
    name="$(basename "$f")"
    out="$TMP/$i.out"
    st="$TMP/$i.exit"
    rc="$(cat "$st" 2>/dev/null)"
    [ -n "$rc" ] || rc=1
    elapsed=$(( $(cat "$TMP/$i.end" 2>/dev/null || cat "$TMP/$i.start") - $(cat "$TMP/$i.start") ))

    # TOO SLOW is per check: perl's alarm kills the check with SIGALRM (142),
    # or the check's own elapsed reached the limit. Never report time.
    too_slow=0
    [ "$rc" -eq 142 ] && too_slow=1
    [ "$elapsed" -ge "$LIMIT" ] && too_slow=1

    if [ "$rc" -eq 0 ] && [ "$too_slow" -eq 0 ]; then
        printf 'ok   %s (%ss)\n' "$name" "$elapsed"
    elif [ "$too_slow" -eq 1 ]; then
        printf 'FAIL %s (TOO SLOW for the fast set (over %s s); fix it or remove its gate-fast marker)\n' \
            "$name" "$LIMIT"
        tail -n 15 "$out" 2>/dev/null | sed 's/^/    /'
        failed=1
    elif [ "$rc" -eq 2 ]; then
        printf 'UNMEASURED %s (exit 2, %ss)\n' "$name" "$elapsed"
        tail -n 15 "$out" 2>/dev/null | sed 's/^/    /'
    else
        printf 'FAIL %s (exit %s, %ss)\n' "$name" "$rc" "$elapsed"
        tail -n 15 "$out" 2>/dev/null | sed 's/^/    /'
        failed=1
    fi
done

[ "$failed" -eq 0 ] || exit 1
exit 0
