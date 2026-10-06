#!/bin/bash
# gate: cheap
# Does tools/close_gate.py refuse `bd close <id>` while the bead's branch
# refs/heads/<id> still exists in the command's working directory, let an
# unknown id through, honour the `-r`/`--reason`/`-m`/`--message` option
# values, ignore `cd` chains and non-close subcommands, honour the
# INCURSION_CLOSE_GATE_OFF=1 bypass, ignore non-Bash tools, and allow on
# garbage input? Defends bead inc-79p2: a bead whose branch is unlanded must
# not be closed before tools/finish_bead.sh runs.
#
# Fully offline: a temp git repo names the branch, so the real repo is never
# touched. "Denied" means the gate's exit code is 2, the same test
# tools/check_dispatch_gate.sh uses for dispatch_gate.py.
#
# Exit: 0 pass, 1 fail, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/tools/close_gate.py"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/close-gate-check.XXXXXX")" || exit 2
REPO="$TMP/repo"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# --- temp git repo with one commit and branch inc-test1 -------------------
mkdir -p "$REPO"
git -C "$REPO" init -q || exit 2
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init || exit 2
git -C "$REPO" branch inc-test1 >/dev/null 2>&1 || exit 2

FAIL=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }

# Build one PreToolUse payload. Usage: payload <tool_name> <command>
payload() {
    python3 - "$1" "$2" "$REPO" <<'PY'
import json, sys
tool, command, cwd = sys.argv[1:4]
print(json.dumps({
    "session_id": "sess-1",
    "transcript_path": "/tmp/t.jsonl",
    "cwd": cwd,
    "hook_event_name": "PreToolUse",
    "tool_name": tool,
    "tool_input": {"command": command},
}))
PY
}

# Run the gate reading the payload from $TMP/in.json. Returns the exit code;
# stderr is left in $TMP/last.stderr.
run_gate() {
    python3 "$GATE" < "$TMP/in.json" > "$TMP/last.out" 2> "$TMP/last.stderr"
    return $?
}

# denied <name> <command>: exit 2, and the stderr names the bead and the
# branch and points at finish_bead.sh. allow <name> <command>: exit 0.
denied() {
    local name="$1" command="$2" rc=0 err
    payload Bash "$command" > "$TMP/in.json"
    run_gate || rc=$?
    err="$(cat "$TMP/last.stderr")"
    if [ "$rc" = 2 ] && grep -q "inc-test1" <<< "$err" \
        && grep -q "refs/heads/inc-test1" <<< "$err" \
        && grep -q "finish_bead.sh" <<< "$err"; then
        pass "$name"
    else
        fail "$name (rc=$rc stderr=$(head -1 "$TMP/last.stderr"))"
    fi
}

allow() {
    local name="$1" command="$2" rc=0
    payload Bash "$command" > "$TMP/in.json"
    run_gate || rc=$?
    if [ "$rc" = 0 ]; then
        pass "$name"
    else
        fail "$name (rc=$rc stderr=$(head -1 "$TMP/last.stderr"))"
    fi
}

# a. `bd close inc-test1` -> denied
denied "a. bd close inc-test1: denied" "bd close inc-test1"

# b. `bd close inc-none` -> allowed
allow "b. bd close inc-none (no branch): allowed" "bd close inc-none"

# c. `bd close inc-none inc-test1 --reason "done"` -> denied
denied "c. bd close inc-none inc-test1 --reason done: denied" \
    'bd close inc-none inc-test1 --reason "done"'

# d. `cd /x && bd close inc-test1` -> denied
denied "d. cd /x && bd close inc-test1: denied" "cd /x && bd close inc-test1"

# e. `bd show inc-test1` -> allowed
allow "e. bd show inc-test1: allowed" "bd show inc-test1"

# f. `bd close inc-test1` with INCURSION_CLOSE_GATE_OFF=1 -> allowed
payload Bash "bd close inc-test1" > "$TMP/in.json"
rc=0
INCURSION_CLOSE_GATE_OFF=1 run_gate || rc=$?
if [ "$rc" = 0 ]; then
    pass "f. bypass env: allowed"
else
    fail "f. bypass env (rc=$rc)"
fi

# g. tool_name "Read" -> allowed
payload Read "bd close inc-test1" > "$TMP/in.json"
rc=0
run_gate || rc=$?
if [ "$rc" = 0 ]; then
    pass "g. tool_name Read: allowed"
else
    fail "g. tool_name Read (rc=$rc)"
fi

# h. garbage on stdin -> allowed, exit 0
rc=0
printf 'not json at all' | python3 "$GATE" > "$TMP/last.out" 2> "$TMP/last.stderr" || rc=$?
if [ "$rc" = 0 ] && [ ! -s "$TMP/last.out" ]; then
    pass "h. garbage stdin: allowed, exit 0, no output"
else
    fail "h. garbage stdin (rc=$rc out=$(cat "$TMP/last.out"))"
fi

# i. `bd close --reason inc-test1 inc-none` -> allowed (inc-test1 is the value
#    of --reason, not a bead id)
allow "i. bd close --reason inc-test1 inc-none: allowed" \
    "bd close --reason inc-test1 inc-none"

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: check_close_gate.sh, all cases"
    exit 0
else
    echo "FAIL: check_close_gate.sh, at least one case failed above"
    exit 1
fi
