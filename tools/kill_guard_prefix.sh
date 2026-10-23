#!/bin/sh
# tools/kill_guard_prefix.sh -- Claude Code shell prefix (bead inc-7zpw).
#
# Claude Code runs EVERY Bash-tool command and EVERY hook command as
# "<prefix> \"<one command string>\"" (one argument) when the env var
# CLAUDE_CODE_SHELL_PREFIX names this script. This is that prefix: it runs the
# command under /bin/zsh, and, when the command carries the subagent marker
# "#kill-guard:subagent" (appended by tools/kill_guard.py for a subagent's Bash
# call), it first applies the Seatbelt sandbox tools/kill_guard.sb so a subagent
# can signal only a process in the same sandbox.
#
# Path with the marker:  first test that the profile applies with
#                        /usr/bin/sandbox-exec -f "$SB" /usr/bin/true (output
#                        discarded). If it applies, exec the sandboxed zsh; if
#                        not (a nested sandbox: it exits 71 with
#                        "sandbox_apply: Operation not permitted"), print one
#                        line to stderr saying the guard could not apply its
#                        sandbox, then run the command unguarded.
# Any other path (no marker): exec /bin/zsh -c "$1" and nothing else -- no
#                        logging, no subshell, no external command. The main
#                        session and every hook take this path, so the main
#                        agent MUST keep working here.
#
# $SB is kill_guard.sb beside this script, resolved from $0 with shell builtins
# only. If this script BREAKS, the main agent fixes it with the Edit tool, which
# needs no shell.

case "$0" in
    */*) SB=${0%/*}/kill_guard.sb ;;
    *)   SB=./kill_guard.sb ;;
esac
SANDBOX_EXEC=/usr/bin/sandbox-exec

case "$1" in
    *#kill-guard:subagent*)
        if "$SANDBOX_EXEC" -f "$SB" /usr/bin/true >/dev/null 2>&1; then
            exec "$SANDBOX_EXEC" -f "$SB" /bin/zsh -c "$1"
        else
            echo "kill_guard_prefix: could not apply the kill guard sandbox (a nested sandbox cannot nest); running unguarded" >&2
            exec /bin/zsh -c "$1"
        fi
        ;;
    *)
        exec /bin/zsh -c "$1"
        ;;
esac
