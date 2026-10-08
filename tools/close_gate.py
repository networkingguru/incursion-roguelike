#!/usr/bin/env python3
"""PreToolUse gate: refuse `bd close <id>` while bead <id>'s branch is unlanded.

WHAT. tools/finish_bead.sh lands a bead and then deletes its branch
`refs/heads/<bead-id>`. So while a branch named after a bead still exists,
that bead has NOT landed. This hook finds every `bd close` in a Bash command,
extracts the bead ids it would close, and denies the call when any of those
ids still has such a branch.

WHY. Agents sometimes run `bd close <id>` before landing; then
tools/check_orphan_branches.sh fails the next landing gate. Bead inc-79p2.
Rule: commit-means-land-the-bead in .claude/rules/bead-and-commit-hygiene.md.

ESCAPE HATCH. Set INCURSION_CLOSE_GATE_OFF=1 in the environment to allow
everything (emergency). Any error -- unreadable JSON, no git -- also allows,
so this hook never blocks unrelated Bash use.

Exit 0 allows; exit 2 denies and prints the reason on stderr. stdlib only.
"""

import json
import os
import re
import shlex
import subprocess
import sys

VALUE_OPTS = {"-r", "--reason", "-m", "--message"}
DENY_MESSAGE = (
    "close gate: refusing `bd close` for {names}. The branch(es) {branches} "
    "still exist, so the bead has not landed. Run `tools/finish_bead.sh <id>` "
    "first, and only then `bd close <id>`. (Emergency override: set "
    "INCURSION_CLOSE_GATE_OFF=1.)\n"
)


def parse_stdin():
    try:
        payload = json.loads(sys.stdin.read())
    except Exception:
        return None
    return payload if isinstance(payload, dict) else None


def split_segments(tokens):
    """Split a token list at shell separators (&& || ; | newline)."""
    seps = {"&&", "||", ";", "|", "\n"}
    segments = [[]]
    for tok in tokens:
        if tok in seps:
            segments.append([])
        else:
            segments[-1].append(tok)
    return segments


def ids_in_segment(segment):
    """In one command segment, find `bd close` and return its bead ids."""
    ids = []
    for i, tok in enumerate(segment):
        base = tok.rsplit("/", 1)[-1]
        if base != "bd" or i + 1 >= len(segment):
            continue
        if segment[i + 1] != "close":
            continue
        j = i + 2
        while j < len(segment):
            tok2 = segment[j]
            if tok2.startswith("-"):
                opt = tok2.split("=", 1)[0]
                if opt in VALUE_OPTS and "=" not in tok2:
                    j += 2
                    continue
                j += 1
                continue
            ids.append(tok2)
            j += 1
    return ids


def ids_via_shlex(command):
    try:
        tokens = shlex.split(command, posix=True)
    except Exception:
        return None
    ids = []
    for segment in split_segments(tokens):
        ids.extend(ids_in_segment(segment))
    return ids


def ids_via_regex(command):
    ids = []
    for line in command.splitlines() or [command]:
        for segment in re.split(r"&&|\|\||;|\|", line):
            tokens = segment.split()
            ids.extend(ids_in_segment(tokens))
    return ids


def bead_ids(command):
    if not command:
        return []
    ids = ids_via_shlex(command)
    if ids is None:
        ids = ids_via_regex(command)
    return ids


def branch_exists(cwd, bead_id):
    if not bead_id:
        return False
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", "refs/heads/" + bead_id],
            cwd=cwd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return False
    return proc.returncode == 0


def main():
    if os.environ.get("INCURSION_CLOSE_GATE_OFF") == "1":
        sys.exit(0)

    payload = parse_stdin()
    if payload is None:
        sys.exit(0)

    if payload.get("tool_name") != "Bash":
        sys.exit(0)

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        sys.exit(0)

    command = tool_input.get("command")
    if not isinstance(command, str):
        sys.exit(0)

    cwd = payload.get("cwd") or os.getcwd()

    offenders = [bid for bid in bead_ids(command) if branch_exists(cwd, bid)]
    if offenders:
        names = ", ".join(offenders)
        branches = ", ".join("refs/heads/" + b for b in offenders)
        print(DENY_MESSAGE.format(names=names, branches=branches),
              file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
