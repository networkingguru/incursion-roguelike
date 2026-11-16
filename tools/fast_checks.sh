#!/usr/bin/env bash
#
# fast_checks.sh -- run the FAST set: the checks that are safe to run on every
# commit, before the landing gate.
#
# WHY THIS EXISTS. Some repository-hygiene checks only run inside the 4-minute
# cheap tier of the landing gate. This runner gives them a separate set, so a
# commit gets fast feedback. It is called by .beads/hooks/pre-commit (from bead
# worktrees only) and by tools/finish_bead.sh before the gate (bead inc-3s7w).
#
# A CHECK JOINS THE FAST SET with one comment line in its first 40 lines:
#   # gate-fast: <reason>
# The reason MUST be non-empty. This marker does NOT change the check's own
# `# gate:` tier.
#
# THE RULE (inc-rst61). A fast check is judged by the KIND of work it does, never
# by time. Six kinds are expensive: game, build, git-history, sleep, bd, compiler.
# tools/fast_probe/ stand-ins record each kind to $INCURSION_FAST_PROBE. A check
# that does one is refused (EXPENSIVE), unless tools/fast_checks.vetted lists it
# for that kind. A check that names git, sleep, bd or a compiler by absolute path
# is refused too, because the stand-ins cannot see it.
# THERE IS NO WALL-CLOCK LIMIT. tools/fast_watch.py watches progress. A watched
# run (INCURSION_FAST_WATCHED=1 in the environment) appends ALERT lines to
# logs/fast-alert.log and lets the check finish. Every other run is unwatched:
# at 5x the alert limits the check stops with a HANG. Only the marker counts:
# CLAUDECODE and NIGHTLY_BRANCH do not change the mode.
#
# Usage: tools/fast_checks.sh [--dir <path>] [--help]
#
# Exit: 0 every fast check passed (a check exiting 2 is UNMEASURED, not a fail)
#       1 at least one fast check failed, hung or was refused as expensive
#       2 no fast check was found, or the runner could not measure
#
set -uo pipefail

CHECK_DIR=""
DIR_GIVEN=0

usage() { sed -n '2,33p' "$0"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)
            [ $# -ge 2 ] || { echo "--dir needs a path" >&2; exit 2; }
            CHECK_DIR="$2"; DIR_GIVEN=1; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

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

# The check's gate tier: the word after '# gate:' in its first 40 lines.
# Prints "none" when there is no such line.
gate_tier() { # <check file>
    local t
    t="$(sed -n '1,40p' "$1" | sed -n 's/^#[[:space:]]*gate:[[:space:]]*//p' | head -1)"
    t="${t%% *}"
    [ -n "$t" ] && printf '%s' "$t" || printf 'none'
}

# Kinds the vetted file allows for a check, comma-separated, or empty.
vetted_kinds() { # <basename>
    [ -f "$VETTED" ] || return 0
    awk -v n="$1" '$0 !~ /^[[:space:]]*#/ && $1 == n { print $2; exit }' "$VETTED"
}

# A non-comment line that names a watched command by absolute path.
FULLPATH_RE='/((usr|opt/homebrew)/)?(local/)?bin/(git|sleep|bd|clang|clang\+\+|cc|c\+\+)([^A-Za-z0-9_]|$)'
fullpath_call() { # <check file>
    grep -vE '^[[:space:]]*#' "$1" | grep -oE "$FULLPATH_RE" | head -1 | sed -E 's/[^A-Za-z0-9_]$//'
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

WATCH="$ROOT/tools/fast_watch.py"
VETTED="$ROOT/tools/fast_checks.vetted"
if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$WATCH" ] || [ ! -d "$ROOT/tools/fast_probe" ]; then
    echo "COULD NOT MEASURE: python3, tools/fast_watch.py and tools/fast_probe/ are needed" >&2
    exit 2
fi

MODE=unwatched
if [ "${INCURSION_FAST_WATCHED:-}" = 1 ]; then
    MODE=watched
fi
ALERT="$ROOT/logs/fast-alert.log"
mkdir -p "$ROOT/logs" || { echo "COULD NOT MEASURE: cannot create $ROOT/logs" >&2; exit 2; }
printf 'RUN %s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MODE" "$$" >> "$ALERT"
printf 'fast checks: %s; alerts go to %s\n' "$MODE" "$ALERT"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fast_checks.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

# Launch every check in parallel under fast_watch.py, with the probe stand-ins
# first on PATH and a fresh probe file. A check that names a watched command by
# absolute path is not run: the probe could not see what it does.
PIDS=()
for i in "${!CHECKS[@]}"; do
    out="$TMP/$i.out"
    st="$TMP/$i.exit"
    start="$TMP/$i.start"
    end="$TMP/$i.end"
    probe="$TMP/$i.probe"
    : > "$probe"
    date +%s > "$start"
    fp="$(fullpath_call "${CHECKS[$i]}")"
    if [ -n "$fp" ]; then
        printf '%s\n' "$fp" > "$TMP/$i.fullpath"
        echo 1 > "$st"; date +%s > "$end"
        continue
    fi
    # A vetted `bd` may wait on the shared beads database: no stall limit for it.
    EX=()
    case ",$(vetted_kinds "$(basename "${CHECKS[$i]}")")," in *,bd,*) EX=( --exempt-wait bd ) ;; esac
    (
        env INCURSION_FAST_PROBE="$probe" PATH="$ROOT/tools/fast_probe:$PATH" \
            python3 "$WATCH" --name "$(basename "${CHECKS[$i]}")" ${EX[@]+"${EX[@]}"} \
            --alert-file "$ALERT" "--$MODE" -- "${CHECKS[$i]}" > "$out" 2>&1
        echo $? > "$st"
        date +%s > "$end"
    ) &
    PIDS+=( "$!" )
done

for p in "${PIDS[@]}"; do
    wait "$p"
done

# Decide each check's verdict. Precedence: HANG, EXPENSIVE, ok, UNMEASURED, FAIL.
VERDICT=()   # ok | hang | expensive | unmeasured | fail
DETAIL=()
ELAPSED=()
RC=()
any_failed=0
for i in "${!CHECKS[@]}"; do
    name="$(basename "${CHECKS[$i]}")"
    rc="$(cat "$TMP/$i.exit" 2>/dev/null)"
    [ -n "$rc" ] || rc=1
    elapsed=$(( $(cat "$TMP/$i.end" 2>/dev/null || cat "$TMP/$i.start") - $(cat "$TMP/$i.start") ))
    RC+=( "$rc" ); ELAPSED+=( "$elapsed" )
    if [ -f "$TMP/$i.fullpath" ]; then
        VERDICT+=( expensive )
        DETAIL+=( "calls $(cat "$TMP/$i.fullpath") by full path, which the probe cannot see" )
        any_failed=1; continue
    fi
    # Kinds recorded, minus the kinds the vetted file allows.
    allowed=",$(vetted_kinds "$name"),"
    bad=""; badlines=""
    for kind in game build git-history sleep bd compiler; do
        line="$(grep -m1 -E "^$kind( |\$)" "$TMP/$i.probe" 2>/dev/null)"
        [ -n "$line" ] || continue
        case "$allowed" in *",$kind,"*) continue ;; esac
        bad="$bad $kind"
        badlines="${badlines:+$badlines; }$kind: $line"
    done
    if [ "$rc" -eq 125 ]; then
        VERDICT+=( hang ); DETAIL+=( "" ); any_failed=1
    elif [ -n "$bad" ]; then
        VERDICT+=( expensive ); DETAIL+=( "$badlines" ); any_failed=1
    elif [ "$rc" -eq 0 ]; then
        VERDICT+=( ok ); DETAIL+=( "" )
    elif [ "$rc" -eq 2 ]; then
        VERDICT+=( unmeasured ); DETAIL+=( "" )
    else
        VERDICT+=( fail ); DETAIL+=( "" ); any_failed=1
    fi
done

# Log each check's timing beside the machine state (inc-b0ziu.8).
for i in "${!CHECKS[@]}"; do
    [ -x "$ROOT/tools/timing_log.sh" ] && "$ROOT/tools/timing_log.sh" fast "$(basename "${CHECKS[$i]}")" "${RC[$i]}" "${ELAPSED[$i]}" >/dev/null
done

# Only when something failed, ask the load guard whether the machine was
# under memory pressure when the checks ran (inc-p8bw). Never consult it on a
# clean set.
GUARD_OUT=""
guard_refused=0
if [ "$any_failed" -eq 1 ]; then
    GUARD_OUT="$( "$ROOT/tools/load_guard.sh" 2>&1 )"
    guard_rc=$?
    [ "$guard_rc" -eq 2 ] && guard_refused=1
fi

if [ "$guard_refused" -eq 1 ]; then
    printf 'OVERLOADED: the machine was under memory pressure when the checks ran, so a failure or HANG below may be memory and not a defect in the check; retry with:\n'
    printf '    until tools/load_guard.sh; do sleep 30; done\n'
    printf '%s\n' "$GUARD_OUT" | sed 's/^/    /'
fi

# Report in discovery order.
failed=0
for i in "${!CHECKS[@]}"; do
    f="${CHECKS[$i]}"
    name="$(basename "$f")"
    out="$TMP/$i.out"
    case "${VERDICT[$i]}" in
        ok)
            printf 'ok   %s (%ss)\n' "$name" "${ELAPSED[$i]}" ;;
        unmeasured)
            printf 'UNMEASURED %s (exit 2, %ss)\n' "$name" "${ELAPSED[$i]}"
            tail -n 15 "$out" 2>/dev/null | sed 's/^/    /' ;;
        hang)
            printf 'HANG %s\n' "$name"
            printf '    see %s; unwatched runs stop a check at 5x the alert limits\n' "$ALERT"
            tail -n 15 "$out" 2>/dev/null | sed 's/^/    /'
            failed=1 ;;
        expensive)
            printf 'EXPENSIVE %s (%s)\n' "$name" "${DETAIL[$i]}"
            advice='move that work out of the check, or ask Brian to vet it in tools/fast_checks.vetted'
            [ "$(gate_tier "$f")" = none ] || advice="$advice; or remove its gate-fast marker (its gate tier still runs it)"
            printf '    %s\n' "$advice"
            tail -n 15 "$out" 2>/dev/null | sed 's/^/    /'
            failed=1 ;;
        *)
            printf 'FAIL %s (exit %s)\n' "$name" "${RC[$i]}"
            tail -n 15 "$out" 2>/dev/null | sed 's/^/    /'
            failed=1 ;;
    esac
done

[ "$failed" -eq 0 ] || exit 1
exit 0
