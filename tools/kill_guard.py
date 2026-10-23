#!/usr/bin/env python3
"""PreToolUse hook (bead inc-7zpw): keep a Claude SUBAGENT from signalling a
process it did not start.

WHAT. When the Claude Agent-tool route fires a Bash PreToolUse hook from inside
a subagent, the hook input carries an `agent_id`. For that input only, this hook
appends ONE line to `tool_input.command`:

    <original command>
    #kill-guard:subagent

The marker is a trailing shell comment: it does not change what the command
does. The sandbox is applied later, by Claude Code's shell prefix
(`CLAUDE_CODE_SHELL_PREFIX` -> tools/kill_guard_prefix.sh), which sees the
marker and runs the command inside a macOS Seatbelt sandbox whose profile
(tools/kill_guard.sb) allows a signal only to a process in the same sandbox.

Every other `tool_input` key (run_in_background, timeout, description, ...) is
passed through unchanged. The updated input is returned in the
`hookSpecificOutput.updatedInput` field Claude Code reads.

WHY NOT A REWRITE. Phase 1 of this bead rewrote the command to `sandbox-exec ...
bash -c '<cmd>'` from the hook. Claude checks its permission rules against the
rewritten text, so an allowlisted `kill` stopped matching and an allowlisted
`kill` was refused ("This command requires approval"), and a deny rule would
stop matching too. Appending a trailing comment line leaves the command text
Claude's rules match intact. Measured: Claude's allowlist still matches a
command with that trailing comment line.

THE MAIN SESSION IS NOT TOUCHED. The owner kills processes from the main session
on purpose, so a hook input with no `agent_id` is left alone (prints nothing).
A command whose last line already is the marker is left alone too: the hook
emits its output with the command unchanged rather than appending a second
marker.

FAIL-OPEN ON UNPARSEABLE INPUT (ponytail: this is the ceiling). Bad or empty
JSON on stdin, or a shape this hook does not recognise, makes it print one line
to stderr and exit 0. It never blocks a session it cannot understand: an
unmarked command is a weaker guard, but a blocked session is a broken one.

Exit 0 always (it marks or it leaves the input alone). stdlib only.
"""

import json
import sys

MARKER = "#kill-guard:subagent"

KILL_WORDS = ("kill", "pkill", "killall")

ADVICE = (
    "kill guard: a subagent may signal only processes started in the same Bash "
    "call; stop your own earlier background jobs with TaskStop, and for a busy "
    "machine wait on tools/load_guard.sh. This is advice only -- the sandbox "
    "enforces the rule."
)


def fail_open(reason):
    sys.stderr.write("kill_guard: %s\n" % reason)
    sys.exit(0)


def main():
    raw = ""
    try:
        raw = sys.stdin.read()
    except Exception as exc:
        fail_open("could not read stdin (%s)" % exc)

    if not raw.strip():
        fail_open("empty input")

    try:
        payload = json.loads(raw)
    except Exception as exc:
        fail_open("unparseable JSON (%s)" % exc)

    if not isinstance(payload, dict):
        fail_open("input is not a JSON object")

    # No agent_id means the main session: the owner kills on purpose. Leave it.
    if not payload.get("agent_id"):
        sys.exit(0)

    if payload.get("tool_name") != "Bash":
        sys.exit(0)

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        fail_open("tool_input is not an object")

    command = tool_input.get("command")
    if not isinstance(command, str):
        fail_open("command is missing or not a string")

    new_input = dict(tool_input)
    # Do not append twice: a command whose last line already is the marker is
    # left alone (marked once).
    if command.split("\n")[-1].rstrip() != MARKER:
        new_input["command"] = command + "\n" + MARKER

    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "updatedInput": new_input,
    }}

    if any(word in command for word in KILL_WORDS):
        out["hookSpecificOutput"]["additionalContext"] = ADVICE

    json.dump(out, sys.stdout)
    sys.stdout.write("\n")
    sys.exit(0)


if __name__ == "__main__":
    main()
