#!/bin/bash
# tools/codex_exec.sh -- run the codex agent harness against one worktree
# under the same stall watchdog as tools/opencode_ds.sh (bead inc-gofz).
#
#   tools/codex_exec.sh <worktree-dir> <brief-file>
#
# Validates the worktree and brief exactly as tools/opencode_ds.sh does:
# the worktree must exist and resolve, must not be the shared checkout
# ~/Scripts/Incursion, and the brief must exist and be non-empty. Exit 2 on
# any refusal.
#
# The run dir is <worktree>/logs/codex/<UTC stamp>-$$ (logs/ is gitignored).
# codex is launched through tools/watchdog.sh with the brief as stdin:
#
#   <codex> exec --json -C <worktree> -s workspace-write \
#       -o <rundir>/last-message.txt -
#
# Override the binary with INCURSION_CODEX_BIN (default: codex). The watchdog
# limits are the INCURSION_WATCHDOG_* env vars documented in
# tools/watchdog.sh; a run it stops writes the reason to
# <rundir>/watchdog.status.
#
# On finish, the wrapper prints last-message.txt if it exists, then a
# rundir=/exit= summary line.
#
# Exit: 0 success, 2 the watchdog fired or codex exited non-zero, 2 on a
# validation refusal.

set -uo pipefail

usage() {
    echo "usage: tools/codex_exec.sh <worktree-dir> <brief-file>" >&2
}

if [ "$#" -ne 2 ]; then
    usage
    exit 2
fi

ARG_WORKTREE="$1"
BRIEF_FILE="$2"

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# --- 1. validate ----------------------------------------------------------
if [ ! -d "$ARG_WORKTREE" ]; then
    echo "refused: worktree directory does not exist: $ARG_WORKTREE" >&2
    exit 2
fi
WORKTREE="$(cd "$ARG_WORKTREE" && pwd -P)" || {
    echo "refused: could not resolve worktree directory: $ARG_WORKTREE" >&2
    exit 2
}
case "$WORKTREE" in
    /*) ;;
    *) echo "refused: worktree did not resolve to an absolute path: $WORKTREE" >&2; exit 2 ;;
esac

if [ ! -f "$BRIEF_FILE" ]; then
    echo "refused: brief file does not exist: $BRIEF_FILE" >&2
    exit 2
fi
if [ ! -s "$BRIEF_FILE" ]; then
    echo "refused: brief file is empty: $BRIEF_FILE" >&2
    exit 2
fi

# The one-worktree-per-bead rule (AGENTS.md): never run in the shared checkout.
SHARED="$HOME/Scripts/Incursion"
if [ -d "$SHARED" ]; then
    SHARED_RESOLVED="$(cd "$SHARED" && pwd -P)"
    if [ "$WORKTREE" = "$SHARED_RESOLVED" ]; then
        echo "refused: $WORKTREE is the shared checkout ($SHARED_RESOLVED)." >&2
        echo "One bead, one worktree: start with tools/worktree.sh <bead-id> and" >&2
        echo "work only in that worktree (AGENTS.md)." >&2
        exit 2
    fi
fi

WATCHDOG="$REPO/tools/watchdog.sh"
if [ ! -f "$WATCHDOG" ]; then
    echo "could not run: missing required file: $WATCHDOG" >&2
    exit 2
fi

# --- 2. run dir -----------------------------------------------------------
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUNDIR="$WORKTREE/logs/codex/${STAMP}-$$"
mkdir -p "$RUNDIR" || { echo "could not run: cannot make run dir $RUNDIR" >&2; exit 2; }

EVENTS="$RUNDIR/events.jsonl"
STDERR="$RUNDIR/stderr.log"
STATUS="$RUNDIR/watchdog.status"
LAST_MESSAGE="$RUNDIR/last-message.txt"

# --- 3. launch ------------------------------------------------------------
CODEX_BIN="${INCURSION_CODEX_BIN:-codex}"

"$WATCHDOG" --in "$BRIEF_FILE" --out "$EVENTS" --err "$STDERR" --status "$STATUS" -- \
    "$CODEX_BIN" exec --json -C "$WORKTREE" -s workspace-write \
    -o "$LAST_MESSAGE" -
CODEX_RC=$?

# The watchdog's exit code is not a signal: codex can exit 124 itself. Read the
# --status file for the reason it stopped the run, if any.
KILLED=""
if [ -f "$STATUS" ]; then
    KILLED="$(head -n 1 "$STATUS" | tr -d '[:space:]')"
fi
case "$KILLED" in
    startup|idle) ;;
    *) KILLED="" ;;
esac

# --- 4. report ------------------------------------------------------------
if [ -f "$LAST_MESSAGE" ]; then
    cat "$LAST_MESSAGE"
fi

if [ -n "$KILLED" ]; then
    echo "rundir=$RUNDIR exit=$CODEX_RC"
    echo "watchdog stopped the run ($KILLED limit); rundir=$RUNDIR" >&2
    exit 2
fi

if [ "$CODEX_RC" -ne 0 ]; then
    echo "rundir=$RUNDIR exit=$CODEX_RC"
    echo "codex exited $CODEX_RC; see $STDERR" >&2
    exit 2
fi

echo "rundir=$RUNDIR exit=$CODEX_RC"
exit 0
