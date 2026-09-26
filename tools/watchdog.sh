#!/bin/bash
# tools/watchdog.sh -- run a command under a two-limit stall watchdog
# (bead inc-gofz).
#
#   tools/watchdog.sh --out <file> --err <file> [--in <file>] [--status <file>]
#                      -- <command> [args...]
#
# Runs <command> in its own process group with stdout redirected to --out
# (which is also the liveness signal), stderr to --err, and stdin from --in
# (default /dev/null). Children the command spawns -- sandbox-exec, opencode,
# bun, bash tool calls -- inherit that group, so stopping the run stops all of
# them.
#
# The watchdog polls the byte size of --out. Two limits stop a stalled run:
#
#   startup  -- if --out is still 0 bytes after INCURSION_WATCHDOG_STARTUP
#               seconds (default 180), stop.
#   idle     -- once --out is non-empty, if its size has not changed for
#               INCURSION_WATCHDOG_IDLE seconds (default 1800), stop.
#
# Env vars (each a positive integer; anything else exits 2):
#
#   INCURSION_WATCHDOG_POLL      polling interval, seconds (default 5)
#   INCURSION_WATCHDOG_STARTUP   startup limit, seconds (default 180)
#   INCURSION_WATCHDOG_IDLE      idle limit, seconds (default 1800)
#   INCURSION_WATCHDOG_GRACE     TERM-to-KILL grace, seconds (default 10)
#
# To stop a run: kill -TERM the whole process group, wait up to the grace,
# then kill -KILL the group, and reap the direct child. On a stop the reason
# ("startup" or "idle") is written to --status if given, one line naming the
# command, the --out file, the reason and the limit in seconds is printed to
# the watchdog's own stderr, and the watchdog exits 124. Otherwise it exits
# with the command's own exit code -- so a caller MUST read the --status file,
# not the exit code, to know whether the watchdog fired (the command can exit
# 124 itself).
#
# On INT or TERM the watchdog forwards TERM to the process group and exits.
#
# Exit: command's own code, or 124 when the watchdog stopped it; 2 on a usage
# or environment error.

set -uo pipefail

usage() {
    echo "usage: tools/watchdog.sh --out <file> --err <file> [--in <file>] [--status <file>] -- <command> [args...]" >&2
}

OUT=""
ERR=""
IN="/dev/null"
STATUS=""
HAVE_CMD=0
CMD=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --out)
            [ "$#" -ge 2 ] || { echo "watchdog: --out needs a file" >&2; usage; exit 2; }
            OUT="$2"; shift 2 ;;
        --err)
            [ "$#" -ge 2 ] || { echo "watchdog: --err needs a file" >&2; usage; exit 2; }
            ERR="$2"; shift 2 ;;
        --in)
            [ "$#" -ge 2 ] || { echo "watchdog: --in needs a file" >&2; usage; exit 2; }
            IN="$2"; shift 2 ;;
        --status)
            [ "$#" -ge 2 ] || { echo "watchdog: --status needs a file" >&2; usage; exit 2; }
            STATUS="$2"; shift 2 ;;
        --)
            shift
            HAVE_CMD=1
            CMD=("$@")
            break ;;
        *)
            echo "watchdog: unknown argument: $1" >&2
            usage
            exit 2 ;;
    esac
done

if [ -z "$OUT" ] || [ -z "$ERR" ]; then
    echo "watchdog: --out and --err are required" >&2
    usage
    exit 2
fi
if [ "$HAVE_CMD" -eq 0 ] || [ "${#CMD[@]}" -eq 0 ]; then
    echo "watchdog: no command given after --" >&2
    usage
    exit 2
fi

# --- env validation -------------------------------------------------------
# Each limit must be a positive integer; a typo like "abc" or "0" must fail
# closed rather than disable a limit.
check_pos_int() {
    local name="$1" value="$2"
    case "$value" in
        ''|*[!0-9]*)
            echo "watchdog: $name must be a positive integer (got: $value)" >&2
            exit 2 ;;
    esac
    if [ "$value" -le 0 ]; then
        echo "watchdog: $name must be a positive integer (got: $value)" >&2
        exit 2
    fi
}

POLL="${INCURSION_WATCHDOG_POLL:-5}"
STARTUP="${INCURSION_WATCHDOG_STARTUP:-180}"
IDLE="${INCURSION_WATCHDOG_IDLE:-1800}"
GRACE="${INCURSION_WATCHDOG_GRACE:-10}"
check_pos_int INCURSION_WATCHDOG_POLL "$POLL"
check_pos_int INCURSION_WATCHDOG_STARTUP "$STARTUP"
check_pos_int INCURSION_WATCHDOG_IDLE "$IDLE"
check_pos_int INCURSION_WATCHDOG_GRACE "$GRACE"

# --- launch ---------------------------------------------------------------
# The command runs under `perl -e 'setpgrp(0,0); exec @ARGV'`, which puts it
# in a fresh process group whose pgid equals the perl process's pid. The
# redirections are explicit on the launched command: bash gives a background
# job /dev/null as stdin when job control is off, so `--in` MUST be stated or
# it would be silently dropped.
CHILD_PID=""
PGID=""

forward_term() {
    if [ -n "$PGID" ]; then
        kill -TERM -- "-$PGID" 2>/dev/null
    fi
    exit 143
}
trap forward_term INT TERM

# stop_run TERM/KILLs the process group, records the reason, and exits 124.
# Defined before the launch and poll so bash has it bound when the loop calls.
stop_run() {
    local reason="$1" limit="$2"

    kill -TERM -- "-$PGID" 2>/dev/null
    local waited=0
    while kill -0 -- "-$PGID" 2>/dev/null && [ "$waited" -lt "$GRACE" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if kill -0 -- "-$PGID" 2>/dev/null; then
        kill -KILL -- "-$PGID" 2>/dev/null
    fi
    wait "$CHILD_PID" 2>/dev/null

    if [ -n "$STATUS" ]; then
        printf '%s\n' "$reason" > "$STATUS"
    fi
    echo "watchdog: stopped (${reason}, ${limit}s): ${CMD[*]} -- out=$OUT" >&2
    exit 124
}

perl -e 'setpgrp(0,0); exec @ARGV or die "exec: $!\n"' -- "${CMD[@]}" \
    < "$IN" > "$OUT" 2> "$ERR" &
CHILD_PID=$!
PGID="$CHILD_PID"

# --- poll -----------------------------------------------------------------
OUT_SIZE=0
LAST_SIZE=0
NONEMPTY=0
IDLE_ELAPSED=0
STARTUP_ELAPSED=0

while kill -0 "$CHILD_PID" 2>/dev/null; do
    sleep "$POLL"
    # Re-check: the child may have exited during the sleep.
    if ! kill -0 "$CHILD_PID" 2>/dev/null; then
        break
    fi

    if [ -f "$OUT" ]; then
        OUT_SIZE="$(wc -c < "$OUT" 2>/dev/null | tr -d ' ')"
    else
        OUT_SIZE=0
    fi
    [ -n "$OUT_SIZE" ] || OUT_SIZE=0

    if [ "$NONEMPTY" -eq 0 ]; then
        if [ "$OUT_SIZE" -gt 0 ]; then
            NONEMPTY=1
            LAST_SIZE="$OUT_SIZE"
            IDLE_ELAPSED=0
        else
            STARTUP_ELAPSED=$((STARTUP_ELAPSED + POLL))
            if [ "$STARTUP_ELAPSED" -ge "$STARTUP" ]; then
                stop_run "startup" "$STARTUP"
            fi
        fi
    else
        if [ "$OUT_SIZE" -ne "$LAST_SIZE" ]; then
            LAST_SIZE="$OUT_SIZE"
            IDLE_ELAPSED=0
        else
            IDLE_ELAPSED=$((IDLE_ELAPSED + POLL))
            if [ "$IDLE_ELAPSED" -ge "$IDLE" ]; then
                stop_run "idle" "$IDLE"
            fi
        fi
    fi
done

# Reap the direct child; `wait` returns its exit status (or 128+signal).
wait "$CHILD_PID"
RC=$?
exit "$RC"
