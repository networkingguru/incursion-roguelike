#!/bin/bash
# gate: cheap
# Does tools/dispatch_gate.py block an unlabelled opus/sonnet/inherited
# Agent/Task dispatch while letting haiku and labelled dispatches through,
# and does it demand TWO stopped DeepSeek runs for the same worktree before
# it honours a `fallback:`? Defends bead inc-xiqb: the hook must name the
# three labels, refuse a fallback with no label, no found run, a run that was
# not stopped by loop/context, or no earlier stopped run for that worktree,
# and log every dispatch it sees.
#
# Fully offline, against a temp ledger and a temp log (env overrides); it never
# touches the real files. Every case asserts the exit code AND exactly one new
# log line carrying the right `decision` and `label`.
#
#   tools/check_dispatch_gate.sh               run the cases
#   tools/check_dispatch_gate.sh --prove-red   mutate the gate so an unlabelled
#                                              sonnet is allowed, confirm the
#                                              "sonnet, no label" case goes
#                                              red, restore, and verify the
#                                              restore with cmp
#
# Exit: 0 pass, 1 fail, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/tools/dispatch_gate.py"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-gate-check.XXXXXX")" || exit 2
LEDGER="$TMP/ledger.jsonl"
LOG="$TMP/dispatch-log.jsonl"
BACKUP=""

cleanup() {
    if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$GATE"
        if cmp -s "$BACKUP" "$GATE"; then
            echo "restored tools/dispatch_gate.py byte-identical to its original"
        else
            echo "COULD NOT CONFIRM tools/dispatch_gate.py WAS RESTORED -- check it by hand" >&2
        fi
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

FAIL=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }

# --- --prove-red ----------------------------------------------------------
# Handled first. Break the label check so an unlabelled sonnet dispatch is
# allowed, re-run this script, expect the "sonnet, no label" case to fail,
# then let the EXIT trap restore the byte-identical original.
if [ "${1:-}" = "--prove-red" ]; then
    BACKUP="$TMP/dispatch_gate.py.orig"
    cp "$GATE" "$BACKUP"

    NEEDLE='    if model_raw == "haiku":'
    if ! grep -qF "$NEEDLE" "$GATE"; then
        echo "could not find the model branch to mutate: $NEEDLE" >&2
        exit 2
    fi
    python3 - "$GATE" "$NEEDLE" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path).read()
# Force the label check to pass: every dispatch is treated as research.
mutated = src.replace(needle, "    if True:  # MUTATED by --prove-red\n"
                              "        label = \"research\"\n"
                              + needle, 1)
open(path, "w").write(mutated)
PY
    echo "mutated tools/dispatch_gate.py: force the label check to pass (unlabelled allowed)"

    MUTATED_OUTPUT="$("$ROOT/tools/check_dispatch_gate.sh")"
    MUTATED_RC=$?
    echo "--- output of the mutated run ---"
    echo "$MUTATED_OUTPUT"
    echo "--- end output of the mutated run ---"

    if [ "$MUTATED_RC" -ne 0 ] && grep -q 'FAIL.*sonnet, no label' <<< "$MUTATED_OUTPUT"; then
        echo "PASS (as intended): the 'sonnet, no label' case went red under the mutation"
        exit 0
    elif [ "$MUTATED_RC" -ne 0 ]; then
        echo "FAIL: the run went red but not on the 'sonnet, no label' case"
        exit 1
    else
        echo "FAIL: check_dispatch_gate.sh stayed green with the label check disabled"
        exit 1
    fi
fi

# --- helpers --------------------------------------------------------------
# Build one PreToolUse payload. Usage: payload <tool_name> <model-or-EMPTY> \
#   <description> <subagent_type>
payload() {
    python3 - "$@" <<'PY'
import json, sys
tool, model, desc, sub = sys.argv[1:5]
ti = {"description": desc, "subagent_type": sub}
if model != "EMPTY":
    ti["model"] = model
print(json.dumps({
    "session_id": "sess-1",
    "transcript_path": "/tmp/t.jsonl",
    "cwd": "/tmp/work",
    "hook_event_name": "PreToolUse",
    "tool_name": tool,
    "tool_input": ti,
}))
PY
}

# Run the gate against a fresh (truncated) log with the temp ledger, reading
# the payload from $TMP/in.json. `env -i` is avoided so PATH survives; extra
# env (for the bypass case) is passed by exporting before the call. Returns the
# gate's exit code; its stderr is left in $TMP/last.stderr.
run_gate() {
    : > "$LOG"
    INCURSION_DISPATCH_LOG="$LOG" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
        python3 "$GATE" < "$TMP/in.json" > "$TMP/last.out" 2> "$TMP/last.stderr"
    return $?
}

log_lines() { wc -l < "$LOG" 2>/dev/null | tr -d ' '; }

# Log field reader: jq is not assumed; use python3.
log_field() { python3 - "$LOG" "$1" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
lines = [l for l in open(path).read().splitlines() if l.strip()]
if not lines:
    print("<no line>")
else:
    print(json.loads(lines[-1]).get(key))
PY
}

expect() {
    local name="$1" want_rc="$2" want_decision="$3" want_label="$4"
    local got_rc="$5" want_lines="$6"
    local got_lines got_decision got_label
    got_lines="$(log_lines)"
    if [ "$got_lines" != "$want_lines" ]; then
        fail "$name (log lines: got $got_lines, want $want_lines)"
        return
    fi
    if [ "$want_lines" = "0" ]; then
        if [ "$got_rc" = "$want_rc" ]; then
            pass "$name"
        else
            fail "$name (rc: got $got_rc, want $want_rc)"
        fi
        return
    fi
    got_decision="$(log_field decision)"
    got_label="$(log_field label)"
    if [ "$got_rc" = "$want_rc" ] && [ "$got_decision" = "$want_decision" ] \
        && [ "$got_label" = "$want_label" ]; then
        pass "$name"
    else
        fail "$name (rc=$got_rc decision=$got_decision label=$got_label; wanted rc=$want_rc decision=$want_decision label=$want_label)"
    fi
}

# --- case: non-Agent tool writes nothing ---------------------------------
payload Bash EMPTY "" general > "$TMP/in.json"
rc=0
run_gate || rc=$?
expect "non-Agent tool (Bash): exit 0, no log line" 0 "" "" "$rc" 0

# --- case: haiku, no label allowed ---------------------------------------
payload Agent haiku "quick search" explore > "$TMP/in.json"
rc=0
run_gate || rc=$?
expect "haiku, no label: allow" 0 allow none "$rc" 1

# --- case: sonnet, no label blocked, stderr names the labels --------------
payload Agent sonnet "do the thing" general > "$TMP/in.json"
rc=0
run_gate || rc=$?
inc_stderr="$(cat "$TMP/last.stderr")"
if [ "$rc" = 2 ] && [ "$(log_lines)" = "1" ] \
    && grep -q "research:" <<< "$inc_stderr" \
    && grep -q "repro-design:" <<< "$inc_stderr" \
    && grep -q "fallback:" <<< "$inc_stderr" \
    && [ "$(log_field decision)" = "block" ] \
    && [ "$(log_field label)" = "none" ]; then
    pass "sonnet, no label: block, stderr names the labels"
else
    fail "sonnet, no label (rc=$rc decision=$(log_field decision) stderr=$(head -1 "$TMP/last.stderr"))"
fi

# --- case: model absent blocked, log model is inherit ---------------------
payload Agent EMPTY "do the thing" general > "$TMP/in.json"
rc=0
run_gate || rc=$?
got_model="$(log_field model)"
if [ "$rc" = 2 ] && [ "$(log_lines)" = "1" ] && [ "$got_model" = "inherit" ] \
    && [ "$(log_field decision)" = "block" ] && [ "$(log_field label)" = "none" ]; then
    pass "model absent, no label: block, log model is inherit"
else
    fail "model absent (rc=$rc model=$got_model decision=$(log_field decision))"
fi

# --- case: research and repro-design labels allowed -----------------------
payload Agent opus "research: read code" general > "$TMP/in.json"
rc=0
run_gate || rc=$?
expect "opus with 'research: read code': allow" 0 allow research "$rc" 1

payload Agent sonnet "Repro-Design: x" general > "$TMP/in.json"
rc=0
run_gate || rc=$?
expect "sonnet with 'Repro-Design: x' (mixed case): allow" 0 allow repro-design "$rc" 1

# --- fallback fixtures ----------------------------------------------------
# Two rows, same worktree. Earlier stopped loop, later stopped context.
WT="/Users/brianhill/Scripts/Incursion-xiqb"
LATER="$WT/logs/opencode/20261003T131816Z-74757"
EARLIER="$WT/logs/opencode/20261003T120000Z-11111"

write_ledger() { printf '%s\n' "$@" > "$LEDGER"; }

# --- case: fallback valid, named by its basename --------------------------
write_ledger \
    "{\"ts\":\"2026-10-03T12:00:00Z\",\"out\":\"$EARLIER\",\"killed\":\"loop\"}" \
    "{\"ts\":\"2026-10-03T13:18:20Z\",\"out\":\"$LATER\",\"killed\":\"context\"}"
payload Agent sonnet "fallback: 20261003T131816Z-74757" general > "$TMP/in.json"
rc=0
run_gate || rc=$?
got_run="$(log_field run)"
if [ "$rc" = 0 ] && [ "$(log_lines)" = "1" ] \
    && [ "$(log_field decision)" = "allow" ] \
    && [ "$(log_field label)" = "fallback" ] \
    && [ "$got_run" = "20261003T131816Z-74757" ]; then
    pass "fallback valid (basename): allow, log run set"
else
    fail "fallback valid (rc=$rc decision=$(log_field decision) run=$got_run)"
fi

# --- case: fallback naming the earlier run (no earlier stopped row) -------
write_ledger \
    "{\"ts\":\"2026-10-03T12:00:00Z\",\"out\":\"$EARLIER\",\"killed\":\"loop\"}" \
    "{\"ts\":\"2026-10-03T13:18:20Z\",\"out\":\"$LATER\",\"killed\":\"context\"}"
payload Agent sonnet "fallback: 20261003T120000Z-11111" general > "$TMP/in.json"
rc=0
run_gate || rc=$?
expect "fallback naming the earlier run: block" 2 block fallback "$rc" 1

# --- case: fallback naming a run with no killed ---------------------------
write_ledger \
    "{\"ts\":\"2026-10-03T12:00:00Z\",\"out\":\"$EARLIER\",\"killed\":\"loop\"}" \
    "{\"ts\":\"2026-10-03T13:18:20Z\",\"out\":\"$LATER\"}"
payload Agent sonnet "fallback: 20261003T131816Z-74757" general > "$TMP/in.json"
rc=0
run_gate || rc=$?
expect "fallback naming a run with no killed: block" 2 block fallback "$rc" 1

# --- case: fallback naming an unknown run ---------------------------------
write_ledger \
    "{\"ts\":\"2026-10-03T12:00:00Z\",\"out\":\"$EARLIER\",\"killed\":\"loop\"}"
payload Agent sonnet "fallback: 20261003T999999Z-00000" general > "$TMP/in.json"
rc=0
run_gate || rc=$?
expect "fallback naming an unknown run: block" 2 block fallback "$rc" 1

# --- case: two stopped rows in DIFFERENT worktrees ------------------------
WT2="/Users/brianhill/Scripts/Incursion-other"
write_ledger \
    "{\"ts\":\"2026-10-03T12:00:00Z\",\"out\":\"$WT2/logs/opencode/20261003T120000Z-22222\",\"killed\":\"loop\"}" \
    "{\"ts\":\"2026-10-03T13:18:20Z\",\"out\":\"$LATER\",\"killed\":\"context\"}"
payload Agent sonnet "fallback: 20261003T131816Z-74757" general > "$TMP/in.json"
rc=0
run_gate || rc=$?
expect "two stopped rows in DIFFERENT worktrees: block" 2 block fallback "$rc" 1

# --- case: bypass env with no label ---------------------------------------
payload Agent opus "do the thing" general > "$TMP/in.json"
rc=0
export INCURSION_DISPATCH_GATE_OFF=1
run_gate || rc=$?
unset INCURSION_DISPATCH_GATE_OFF
expect "bypass env with no label: exit 0, decision bypass" 0 bypass none "$rc" 1

# --- case: stdin not json -------------------------------------------------
: > "$LOG"
rc=0
printf 'not json' | INCURSION_DISPATCH_LOG="$LOG" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$GATE" > /dev/null 2> "$TMP/err.txt" || rc=$?
if [ "$rc" = 2 ] && [ "$(log_lines)" = "0" ] \
    && grep -qi "could not read its input" "$TMP/err.txt"; then
    pass "stdin not json: exit 2"
else
    fail "stdin not json (rc=$rc lines=$(log_lines))"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: check_dispatch_gate.sh, all cases"
    exit 0
else
    echo "FAIL: check_dispatch_gate.sh, at least one case failed above"
    exit 1
fi
