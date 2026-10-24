#!/bin/bash
# gate: cheap
#
# Does the Claude subagent kill guard keep an implementer from signalling a
# process it did not start (bead inc-7zpw)?
#
# The guard has two parts. tools/kill_guard.py is a PreToolUse hook on the Bash
# tool: when the hook input carries an `agent_id` (the hook fired from inside a
# subagent) it appends ONE line, `#kill-guard:subagent`, to the command and
# keeps every other tool_input key; the main session (no `agent_id`) is left
# alone. tools/kill_guard_prefix.sh is the shell prefix Claude Code installs via
# CLAUDE_CODE_SHELL_PREFIX: when the command string holds that marker it applies
# the Seatbelt sandbox tools/kill_guard.sb (which allows a signal only to a
# process in the same sandbox) before running the command; every other command
# runs unguarded, so the main session keeps working.
#
# This check drives tools/kill_guard.py DIRECTLY with hand-written hook JSON and
# runs the hook's output command through tools/kill_guard_prefix.sh exactly as
# Claude does: kill_guard_prefix.sh "<one command string>". It starts its own
# outside processes and requires that a subagent's marked `kill` and `pkill`
# cannot signal them, while a process started in the same shell still dies. It
# also checks the prefix is transparent on the unmarked path. Every process it
# starts it also kills on exit, outside any sandbox.
#
# This check reads no game state, so it depends on no seed. The only facts it
# reads are its own constants and the tools it drives; those are fixed by the
# files it names, not by a seed. Per docs/VERIFICATION.md, "A check must not
# depend on the seed": a check that reads nothing the seed decides cannot be
# moved by appending a resource. Listed for the record:
#   # fact: sandbox-exec applies a profile -- this machine's Seatbelt (positive control)
#   # fact: applying a different sandbox profile inside a sandbox fails -- this machine's Seatbelt (negative control)
#   # fact: the hook appends the marker once -- tools/kill_guard.py, driven with fixed JSON
#   # fact: a marked command runs sandboxed -- tools/kill_guard_prefix.sh, given a fixed string
#   # fact: an unmarked command runs -- tools/kill_guard_prefix.sh, given a fixed string
#   # fact: a killed process is dead once kill -0 fails or ps shows state Z -- polled up to 5 s by dies_within
#
#   tools/check_kill_guard.sh
#   tools/check_kill_guard.sh --selftest   # assertion (j): prove the check
#                                          # goes red when the marked command is
#                                          # run unwrapped (the outside sleep dies)
#
# Exit: 0 pass, 1 fail, 2 could not run / unmeasured.
#
# NOTE: sandbox-exec cannot nest. Run this OUTSIDE any sandbox (the Claude
# session does). Inside one, assertion (a)'s positive control fails and the
# whole check is reported UNMEASURED -- that is how a nested sandbox shows up,
# not a bug in the guard. Assertions (i) and (i2) exercise the nested case on
# purpose: (i) runs the prefix itself under a loose outer profile (the inner
# sandbox cannot apply, so the prefix warns and runs unguarded) and (i2) runs it
# under kill_guard.sb itself (the inner sandbox applies, so no warning).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/tools/kill_guard.py"
PREFIX="$ROOT/tools/kill_guard_prefix.sh"
PROFILE="$ROOT/tools/kill_guard.sb"
MARKER="#kill-guard:subagent"

SELFTEST=0
if [ "${1:-}" = "--selftest" ]; then
    SELFTEST=1
fi

TMPDIR_KG="$(mktemp -d)"
LOOSE_PROFILE="$TMPDIR_KG/loose.sb"

OUTSIDE_PIDS=""
cleanup() {
    if [ -n "$OUTSIDE_PIDS" ]; then
        for p in $OUTSIDE_PIDS; do kill -KILL "$p" 2>/dev/null; done
    fi
    [ -n "$TMPDIR_KG" ] && rm -rf "$TMPDIR_KG"
}
trap cleanup EXIT

FAIL=0
UNMEASURED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }
unmeasured() { echo "UNMEASURED  $1"; UNMEASURED=1; }

# start_outside <cmd...>: start a process outside any sandbox, remember its pid,
# and print it. stdout/stderr go to /dev/null so a command substitution that
# captures the pid does not wait for the child to close the pipe.
start_outside() {
    "$@" >/dev/null 2>&1 &
    local pid=$!
    OUTSIDE_PIDS="$OUTSIDE_PIDS $pid"
    printf '%s' "$pid"
}

# alive <pid>: 0 if the process is still running.
alive() { kill -0 "$1" 2>/dev/null; }

# dies_within <pid> <seconds>: 0 once the process is gone or a zombie. kill(2)
# only posts the signal, and kill -0 succeeds on a zombie (inc-qi0g).
dies_within() {
    local pid="$1" tries=$(( $2 * 10 )) st
    while [ "$tries" -gt 0 ]; do
        alive "$pid" || return 0
        st="$(ps -o stat= -p "$pid" 2>/dev/null)"
        case "$st" in Z*) return 0 ;; esac
        sleep 0.1
        tries=$((tries - 1))
    done
    return 1
}

if [ ! -f "$HOOK" ]; then
    echo "UNMEASURED: check_kill_guard.sh ($HOOK missing)"
    exit 2
fi
if [ ! -f "$PREFIX" ]; then
    echo "UNMEASURED: check_kill_guard.sh ($PREFIX missing)"
    exit 2
fi
if [ ! -f "$PROFILE" ]; then
    echo "UNMEASURED: check_kill_guard.sh ($PROFILE missing)"
    exit 2
fi
if ! command -v sandbox-exec >/dev/null 2>&1; then
    echo "UNMEASURED: check_kill_guard.sh (sandbox-exec missing)"
    exit 2
fi

# A loose outer profile: allows everything, including sandbox-exec, so a nested
# sandbox can be attempted from inside it.
printf '(version 1)\n(allow default)\n' > "$LOOSE_PROFILE"

# hook_rewrite <json-on-stdin>: run the hook, print its stdout.
hook_rewrite() {
    "$HOOK"
}

# extract_updated_command <hook_json>: print tool_input.command from the hook's
# output, or nothing if the hook printed no updatedInput.
extract_updated_command() {
    python3 -c '
import json, sys
try:
    doc = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
hso = doc.get("hookSpecificOutput", {})
ui = hso.get("updatedInput", {})
cmd = ui.get("command")
if isinstance(cmd, str):
    sys.stdout.write(cmd)
'
}

# --- (a) positive control: the profile applies and does not block exec --------
echo "# (a) positive control: sandbox-exec applies tools/kill_guard.sb"
if sandbox-exec -f "$PROFILE" /usr/bin/true >/dev/null 2>&1; then
    pass "positive control: sandbox-exec -f tools/kill_guard.sb /usr/bin/true succeeds"
else
    rc=$?
    unmeasured "positive control failed (rc=$rc); a nested or broken sandbox makes every other result meaningless"
    echo "UNMEASURED: check_kill_guard.sh (positive control; sandbox-exec cannot nest)"
    exit 2
fi

# --- (b) main session: no agent_id -> empty stdout ---------------------------
echo "# (b) main session (no agent_id) is not rewritten"
MAIN_JSON='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"}}'
MAIN_OUT="$(printf '%s' "$MAIN_JSON" | hook_rewrite)"
if [ -z "$MAIN_OUT" ]; then
    pass "no agent_id: hook prints nothing"
else
    fail "no agent_id: hook printed output (expected nothing): $MAIN_OUT"
fi

# --- (c) subagent, kill by PID: outside sleep survives -----------------------
echo "# (c) subagent kill by PID cannot signal an outside process"
SLEEP_PID="$(start_outside /bin/sleep 300)"
if ! alive "$SLEEP_PID"; then
    unmeasured "could not start the outside sleep for the PID test"
else
    C_JSON="$(python3 -c '
import json, sys
pid = sys.argv[1]
doc = {
  "hook_event_name": "PreToolUse",
  "agent_id": "selftest-agent",
  "tool_name": "Bash",
  "tool_input": {"command": "kill " + pid},
}
sys.stdout.write(json.dumps(doc))
' "$SLEEP_PID")"
    C_CMD="$(printf '%s' "$C_JSON" | hook_rewrite | extract_updated_command)"
    if [ -z "$C_CMD" ]; then
        fail "subagent kill by PID: hook produced no marked command"
    elif [ "$SELFTEST" -eq 1 ]; then
        # (j) red control: run the MARKED command through plain /bin/zsh -c,
        # NOT the prefix, and require the outside sleep to die.
        /bin/zsh -c "$C_CMD" >/dev/null 2>&1
        U_RC=$?
        if [ "$U_RC" -eq 0 ] && dies_within "$SLEEP_PID" 5; then
            pass "selftest: unwrapped kill killed the outside sleep (the check can go red)"
        elif [ "$U_RC" -ne 0 ]; then
            unmeasured "selftest: the unwrapped kill itself was denied (rc=$U_RC); run outside any sandbox to measure the red control"
        else
            fail "selftest: unwrapped kill did NOT kill the outside sleep; this check cannot be shown red"
        fi
    else
        C_OUT="$("$PREFIX" "$C_CMD" 2>&1)"
        if alive "$SLEEP_PID"; then
            pass "subagent kill by PID: the outside sleep is still alive"
        else
            fail "subagent kill by PID: the outside sleep DIED (guard did not hold)"
        fi
        # zsh prints the Seatbelt refusal lower case: match case-insensitively.
        if grep -qi "operation not permitted" <<< "$C_OUT"; then
            pass "subagent kill by PID: the run reported \"operation not permitted\""
        else
            fail "subagent kill by PID: no \"operation not permitted\" in the run output: $C_OUT"
        fi
    fi
fi

# --- (d) subagent, kill by name (pkill -f) -----------------------------------
echo "# (d) subagent pkill -f cannot signal an outside process"
MARKER_PROC="inc-7zpw-kill-guard-marker-$$"
# A process whose argv carries the marker: exec -a sets argv[0].
DPID="$(start_outside /bin/bash -c "exec -a '$MARKER_PROC' /bin/sleep 301")"
sleep 0.3
if ! alive "$DPID"; then
    unmeasured "could not start the outside marker process for the name test"
else
    D_JSON="$(python3 -c '
import json, sys
marker = sys.argv[1]
doc = {
  "hook_event_name": "PreToolUse",
  "agent_id": "selftest-agent",
  "tool_name": "Bash",
  "tool_input": {"command": "pkill -f " + marker},
}
sys.stdout.write(json.dumps(doc))
' "$MARKER_PROC")"
    D_CMD="$(printf '%s' "$D_JSON" | hook_rewrite | extract_updated_command)"
    if [ -z "$D_CMD" ]; then
        fail "subagent pkill -f: hook produced no marked command"
    elif [ "$SELFTEST" -eq 1 ]; then
        /bin/zsh -c "$D_CMD" >/dev/null 2>&1
        U_RC=$?
        if [ "$U_RC" -eq 0 ] && dies_within "$DPID" 5; then
            pass "selftest: unwrapped pkill -f killed the outside marker process (the check can go red)"
        elif [ "$U_RC" -ne 0 ]; then
            unmeasured "selftest: the unwrapped pkill itself was denied (rc=$U_RC); run outside any sandbox to measure the red control"
        else
            fail "selftest: unwrapped pkill -f did NOT kill the outside marker process; cannot be shown red"
        fi
    else
        D_OUT="$("$PREFIX" "$D_CMD" 2>&1)"
        if alive "$DPID"; then
            pass "subagent pkill -f: the outside marker process is still alive"
        else
            fail "subagent pkill -f: the outside marker process DIED (guard did not hold)"
        fi
    fi
fi

# --- (e) own process: a process started in the same shell still dies ---------
echo "# (e) a subagent can still kill a process it starts in the same shell"
E_JSON='{"hook_event_name":"PreToolUse","agent_id":"selftest-agent","tool_name":"Bash","tool_input":{"command":"sleep 300 & k=$!; kill $k; wait $k; echo rc=$?"}}'
E_CMD="$(printf '%s' "$E_JSON" | hook_rewrite | extract_updated_command)"
if [ -z "$E_CMD" ]; then
    fail "own process: hook produced no marked command"
else
    E_OUT="$("$PREFIX" "$E_CMD" 2>&1)"
    case "$E_OUT" in
        *"rc=143"*)
            pass "own process: the sandboxed shell killed its own sleep (rc=143)" ;;
        *)
            fail "own process: expected rc=143 (terminated by SIGTERM), got: $E_OUT" ;;
    esac
fi

# --- (f) other tool_input keys survive; the marker is appended once ----------
echo "# (f) run_in_background, timeout and description survive; marker appended once"
F_JSON='{"hook_event_name":"PreToolUse","agent_id":"selftest-agent","tool_name":"Bash","tool_input":{"command":"kill 1","run_in_background":true,"timeout":42000,"description":"a kill"}}'
F_CHECK="$(printf '%s' "$F_JSON" | hook_rewrite | python3 -c '
import json, sys
marker = "#kill-guard:subagent"
try:
    doc = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
ui = doc.get("hookSpecificOutput", {}).get("updatedInput", {})
keys = ui.get("run_in_background") is True and ui.get("timeout") == 42000 and ui.get("description") == "a kill"
cmd = ui.get("command", "")
once = cmd == "kill 1\n" + marker
sys.stdout.write("ok" if (keys and once) else "bad:" + json.dumps({k: ui.get(k) for k in ("run_in_background", "timeout", "description", "command")}))
')"
if [ "$F_CHECK" = "ok" ]; then
    pass "run_in_background, timeout and description are unchanged; marker appended once"
else
    fail "a tool_input key changed, or the marker was not appended exactly once: $F_CHECK"
fi
# Feed an already-marked command: it must be left unchanged (not appended twice).
F2_CHECK="$(printf '%s' "{\"hook_event_name\":\"PreToolUse\",\"agent_id\":\"selftest-agent\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"kill 1\\n$MARKER\"}}" | hook_rewrite | python3 -c '
import json, sys
marker = "#kill-guard:subagent"
try:
    doc = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
ui = doc.get("hookSpecificOutput", {}).get("updatedInput", {})
cmd = ui.get("command", "")
sys.stdout.write("ok" if cmd == "kill 1\n" + marker else "bad:" + json.dumps(cmd))
')"
if [ "$F2_CHECK" = "ok" ]; then
    pass "an already-marked command is left unchanged (not appended twice)"
else
    fail "an already-marked command was changed: $F2_CHECK"
fi

# --- (g) additionalContext present for a kill, absent for echo hi ------------
echo "# (g) additionalContext is present for a kill command, absent for echo hi"
G_KILL="$(printf '%s' "$F_JSON" | hook_rewrite | python3 -c '
import json, sys
doc = json.loads(sys.stdin.read())
ctx = doc.get("hookSpecificOutput", {}).get("additionalContext", "")
sys.stdout.write("yes" if ctx else "no")
')"
# The echo case must be a subagent to reach the marking path at all.
G_ECHO_SUB="$(printf '%s' '{"hook_event_name":"PreToolUse","agent_id":"selftest-agent","tool_name":"Bash","tool_input":{"command":"echo hi"}}' | hook_rewrite | python3 -c '
import json, sys
doc = json.loads(sys.stdin.read())
ctx = doc.get("hookSpecificOutput", {}).get("additionalContext", "")
sys.stdout.write("yes" if ctx else "no")
')"
if [ "$G_KILL" = "yes" ]; then
    pass "additionalContext present for a kill command"
else
    fail "additionalContext missing for a kill command"
fi
if [ "$G_ECHO_SUB" = "no" ]; then
    pass "additionalContext absent for a subagent echo hi"
else
    fail "additionalContext unexpectedly present for echo hi"
fi

# --- (h) the plain path is transparent ---------------------------------------
echo "# (h) the unmarked prefix path is transparent (stdout, exit code, stdin, quoting)"
# stdout and exit code pass through.
H1="$("$PREFIX" 'echo hi; exit 7'; echo "rc=$?")"
case "$H1" in
    *"hi"*"rc=7"*)
        pass "unmarked: stdout and exit code pass through (echo hi; exit 7)" ;;
    *)
        fail "unmarked: stdout/exit did not pass through: $H1" ;;
esac
# stdin passes through.
H2="$(printf 'x\n' | "$PREFIX" 'cat')"
if [ "$H2" = "x" ]; then
    pass "unmarked: stdin passes through (printf x | prefix cat)"
else
    fail "unmarked: stdin did not pass through: $H2"
fi
# A command with single quotes, double quotes, $, a newline and a heredoc runs
# exactly as /bin/zsh -c runs it.
TRICKY='echo "$HOME" '"'"'sq'"'"'
cat <<EOF
heredoc line
EOF
echo $$ >/dev/null; echo done'
ZSH_OUT="$(/bin/zsh -c "$TRICKY" 2>&1)"
PFX_OUT="$("$PREFIX" "$TRICKY" 2>&1)"
if [ "$ZSH_OUT" = "$PFX_OUT" ]; then
    pass "unmarked: tricky command matches /bin/zsh -c byte for byte"
else
    fail "unmarked: tricky command differs from /bin/zsh -c; zsh=[$ZSH_OUT] prefix=[$PFX_OUT]"
fi
# An outside process CAN be killed: the main session is not guarded.
H4_PID="$(start_outside /bin/sleep 302)"
if ! alive "$H4_PID"; then
    unmeasured "could not start the outside sleep for the main-session test"
else
    "$PREFIX" "kill $H4_PID" >/dev/null 2>&1
    if dies_within "$H4_PID" 5; then
        pass "unmarked: an outside process CAN be killed (the main session is not guarded)"
    else
        fail "unmarked: an outside process could not be killed (the prefix over-guards)"
    fi
fi

# --- (i) nested sandbox: the marked path degrades gracefully -----------------
# The outer profile must itself allow sandbox-exec (a loose profile: "(version 1)"
# and "(allow default)"). Under the SAME kill_guard.sb as the outer profile the
# prefix's inner sandbox applies (see (i2)), so no warning is due there; only a
# DIFFERENT outer profile makes the inner apply fail and the warning fire. The
# loose profile lives in the temp dir removed by the EXIT trap.
echo "# (i) a marked command under a nested loose sandbox still runs and warns"
I_ALL="$(sandbox-exec -f "$LOOSE_PROFILE" "$PREFIX" "echo ran
$MARKER" 2>&1)"
I_RC=$?
case "$I_ALL" in
    *"ran"*) pass "nested sandbox: the marked echo ran" ;;
    *)       fail "nested sandbox: expected \"ran\" in the output, got: $I_ALL" ;;
esac
if [ "$I_RC" -eq 0 ]; then
    pass "nested sandbox: the prefix did not fail (exit 0)"
else
    fail "nested sandbox: the prefix failed (rc=$I_RC): $I_ALL"
fi
case "$I_ALL" in
    *"could not apply the kill guard sandbox"*)
        pass "nested sandbox: the prefix said the guard could not apply its sandbox" ;;
    *)
        fail "nested sandbox: no warning about the sandbox not applying: $I_ALL" ;;
esac

# --- (i2) same profile inside: no warning, still runs -------------------------
# With kill_guard.sb as the outer profile, the prefix's inner sandbox applies,
# so the command runs and there is NO warning line.
echo "# (i2) a marked command under an outer kill_guard.sb runs with no warning"
I2_ALL="$(sandbox-exec -f "$PROFILE" "$PREFIX" "echo ran
$MARKER" 2>&1)"
I2_RC=$?
case "$I2_ALL" in
    *"ran"*) pass "same-profile nest: the marked echo ran" ;;
    *)       fail "same-profile nest: expected \"ran\" in the output, got: $I2_ALL" ;;
esac
if [ "$I2_RC" -eq 0 ]; then
    pass "same-profile nest: the prefix did not fail (exit 0)"
else
    fail "same-profile nest: the prefix failed (rc=$I2_RC): $I2_ALL"
fi
case "$I2_ALL" in
    *"could not apply the kill guard sandbox"*)
        fail "same-profile nest: the prefix warned the sandbox could not apply: $I2_ALL" ;;
    *)
        pass "same-profile nest: no warning about the sandbox not applying" ;;
esac

# --- (k) escape attempt: a marked command cannot sandbox its way to a kill ---
# A subagent's marked command starts a FRESH loose profile and a `sandbox-exec -p`
# inline profile and, under each, tries to kill an outside pid. Because the
# marked command is already inside kill_guard.sb, applying a different sandbox
# fails, so the kill never runs and the outside sleep MUST survive.
echo "# (k) a marked command cannot sandbox its way to an outside kill"
K_PID="$(start_outside /bin/sleep 303)"
if ! alive "$K_PID"; then
    unmeasured "could not start the outside sleep for the escape test"
else
    K_CMD="sandbox-exec -f $LOOSE_PROFILE /bin/kill $K_PID; sandbox-exec -p '(version 1)(allow default)' /bin/kill $K_PID; echo tried
$MARKER"
    "$PREFIX" "$K_CMD" >/dev/null 2>&1
    if alive "$K_PID"; then
        pass "escape attempt: the outside sleep is still alive"
    else
        fail "escape attempt: the outside sleep DIED (guard did not hold)"
    fi
fi

# --- (j) selftest summary ----------------------------------------------------
if [ "$SELFTEST" -eq 1 ]; then
    echo "# (j) selftest: the marked command run unwrapped was shown to go red"
else
    echo "# (j) run with --selftest to show the marked kill run unwrapped goes red"
fi

echo
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: check_kill_guard.sh, at least one assertion failed above"
    exit 1
fi
if [ "$UNMEASURED" -ne 0 ]; then
    echo "UNMEASURED: check_kill_guard.sh, at least one assertion could not be measured"
    exit 2
fi
echo "PASS: check_kill_guard.sh"
exit 0
