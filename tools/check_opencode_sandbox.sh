#!/bin/bash
# gate: cheap
#
# Does the DeepSeek implementer harness keep its secrets out of reach (bead
# inc-k4wc)? Two halves:
#
#   Part 1 -- secrets unreadable under the real Seatbelt profile
#   (tools/opencode/sandbox.sb): the login Keychain, ~/.ssh, the gh token and
#   the other named stores must all fail to read inside the sandbox that
#   tools/opencode_ds.sh applies. Each probe is first run OUTSIDE the sandbox:
#   if it already fails there the probe cannot establish anything and is
#   UNMEASURED, which fails the check -- never passes. A positive control (cat
#   of a file the check wrote into WORKDIR) must succeed inside the sandbox, or
#   the whole part is UNMEASURED (this is also how a nested sandbox, where
#   sandbox-exec refuses to apply, is detected).
#
#   Part 2 -- the API key never reaches an argv: tools/opencode_ds.sh is run
#   against a temp worktree with a random canary key and a silent fake opencode
#   binary. While it runs, `ps -axww -o args=` is sampled and must not show the
#   canary; after it exits, neither the wrapper's stdout/stderr nor any file
#   under the worktree's logs/ may hold it. The watchdog MUST have stopped the
#   run (the stop message present), or the leak path was never exercised and
#   the part is UNMEASURED (non-zero).
#
#   tools/check_opencode_sandbox.sh
#
# Exit: 0 pass, 1 fail, 2 could not run / unmeasured.
#
# NOTE: sandbox-exec cannot nest. Run this OUTSIDE any sandbox (the Claude
# session does); inside one, Part 1's positive control fails and is reported
# UNMEASURED.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="$ROOT/tools/opencode/sandbox.sb"
WRAPPER="$ROOT/tools/opencode_ds.sh"
DEEPSEEK_MODULE="$ROOT/tools/deepseek.py"

TMP="$(mktemp -d)" || exit 2
WORKDIR=""
CACHEDIR=""
PART2_PIDS=""

cleanup() {
    if [ -n "$PART2_PIDS" ]; then
        for p in $PART2_PIDS; do kill -KILL "$p" 2>/dev/null; done
    fi
    rm -rf "$TMP"
    if [ -n "$WORKDIR" ]; then rm -rf "$WORKDIR"; fi
    if [ -n "$CACHEDIR" ]; then rm -rf "$CACHEDIR"; fi
}
trap cleanup EXIT

FAIL=0
UNMEASURED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }
unmeasured() { echo "UNMEASURED  $1"; UNMEASURED=1; }

if ! command -v sandbox-exec >/dev/null 2>&1; then
    unmeasured "sandbox-exec is not available; nothing can be measured"
    echo "UNMEASURED: check_opencode_sandbox.sh (sandbox-exec missing)"
    exit 2
fi

# --- Part 1: secrets unreadable under the real profile --------------------
echo "# Part 1: secrets unreadable under tools/opencode/sandbox.sb"

WORKDIR="$(mktemp -d)" || exit 2
CACHEDIR="$(mktemp -d)" || exit 2

# The positive control proves the sandbox actually applies AND that reading a
# WORKDIR file is permitted: without it a "everything reads fail" result could
# just be sandbox-exec refusing to nest.
CONTROL="$WORKDIR/control.txt"
printf 'sandbox-positive-control\n' > "$CONTROL"

sandboxed() {
    sandbox-exec -f "$PROFILE" \
        -D WORKDIR="$WORKDIR" -D CACHEDIR="$CACHEDIR" -D HOME="$HOME" \
        "$@" >/dev/null 2>&1
}

CONTROL_OK=1
sandboxed cat "$CONTROL"
CONTROL_RC=$?
if [ "$CONTROL_RC" -ne 0 ]; then
    CONTROL_OK=0
    unmeasured "positive control: cat of a WORKDIR file failed inside the sandbox (rc=$CONTROL_RC)"
else
    pass "positive control: a WORKDIR file is readable inside the sandbox"
fi

# SERVICE comes from tools/deepseek.py so the check tracks that constant.
SERVICE="$(python3 - "$DEEPSEEK_MODULE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("deepseek", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
sys.stdout.write(mod.SERVICE)
PY
)"
if [ -z "$SERVICE" ]; then
    unmeasured "could not read SERVICE from tools/deepseek.py"
fi

# probe <label> <cmd...>
# Runs the command outside, then inside, both with output discarded (no secret
# may ever be printed). Outside failure -> UNMEASURED. Inside success -> FAIL.
probe() {
    local label="$1"; shift

    "$@" >/dev/null 2>&1
    local outside_rc=$?
    if [ "$outside_rc" -ne 0 ]; then
        unmeasured "$label: probe fails OUTSIDE the sandbox (rc=$outside_rc); cannot establish anything"
        return
    fi

    # If the sandbox itself did not apply (the positive control failed, e.g.
    # sandbox-exec refusing to nest), every "denied inside" is meaningless.
    if [ "$CONTROL_OK" -eq 0 ]; then
        unmeasured "$label: NOT evaluated (the sandbox did not apply; see the positive control)"
        return
    fi

    sandboxed "$@"
    local inside_rc=$?
    if [ "$inside_rc" -ne 0 ]; then
        pass "$label: readable outside (rc=0), denied inside (rc=$inside_rc)"
    else
        fail "$label: readable inside the sandbox (rc=0)"
    fi
}

probe "keychain incursion-openrouter" \
    security find-generic-password -s incursion-openrouter -w
if [ -n "$SERVICE" ]; then
    probe "keychain $SERVICE" \
        security find-generic-password -s "$SERVICE" -w
fi
probe "~/.ssh" ls "$HOME/.ssh"
probe "~/.config/gh/hosts.yml" cat "$HOME/.config/gh/hosts.yml"
probe "gh auth token" gh auth token

# --- Part 2: the key never leaks through the wrapper ----------------------
echo "# Part 2: the API key never reaches an argv"

CANARY="canary-$(uuidgen)"

# A silent fake opencode: it writes nothing, so the watchdog's startup limit
# fires and the stop path (the one that used to print the whole argv) runs.
FAKE_DIR="$TMP/fakebin"; mkdir -p "$FAKE_DIR"
FAKE="$FAKE_DIR/opencode"
cat > "$FAKE" <<'FAKE_EOF'
#!/bin/bash
sleep 30
FAKE_EOF
chmod +x "$FAKE"

WT="$TMP/wt"; mkdir -p "$WT"
BRIEF="$TMP/brief.txt"
printf 'do a thing\n' > "$BRIEF"
LEDGER="$TMP/ledger.jsonl"
: > "$LEDGER"
RUNS_DIR="$TMP/runs"
mkdir -p "$RUNS_DIR"
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME"

OUT="$TMP/p2.out"
ERR="$TMP/p2.err"

HOME="$FAKE_HOME" \
INCURSION_DEEPSEEK_KEY="$CANARY" \
INCURSION_OPENCODE_BIN="$FAKE" \
INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
INCURSION_OPENCODE_RUNS_DIR="$RUNS_DIR" \
INCURSION_WATCHDOG_STARTUP=2 \
INCURSION_WATCHDOG_POLL=1 \
    "$WRAPPER" "$WT" "$BRIEF" > "$OUT" 2> "$ERR" &
WRAPPER_PID=$!
PART2_PIDS="$WRAPPER_PID"

SEEN_BIN=0
CANARY_IN_PS=0
DEADLINE=$((SECONDS + 30))
while kill -0 "$WRAPPER_PID" 2>/dev/null && [ "$SECONDS" -lt "$DEADLINE" ]; do
    SAMPLE="$(ps -axww -o args= 2>/dev/null)"
    case "$SAMPLE" in *"$FAKE"*) SEEN_BIN=1 ;; esac
    case "$SAMPLE" in *"$CANARY"*) CANARY_IN_PS=1 ;; esac
    sleep 0.2
done

wait "$WRAPPER_PID"
PART2_PIDS=""

if [ "$SEEN_BIN" -eq 0 ]; then
    unmeasured "the fake opencode never appeared in ps; the leak path was never exercised"
else
    pass "the fake opencode ran (seen in ps) and was sampled"
fi

if [ "$CANARY_IN_PS" -eq 1 ]; then
    fail "the canary key appeared in ps argv"
else
    pass "the canary key never appeared in ps argv"
fi

if grep -q 'watchdog stopped the run' "$ERR"; then
    pass "the watchdog stopped the run (stop message present)"
else
    unmeasured "the watchdog did not stop the run; the stop path (argv leak) was never exercised"
fi

# The canary must not appear in stdout, stderr, nor any file the run wrote.
LEAK=0
grep -qF "$CANARY" "$OUT" 2>/dev/null && LEAK=1
grep -qF "$CANARY" "$ERR" 2>/dev/null && LEAK=1
grep -rqF "$CANARY" "$WT" 2>/dev/null && LEAK=1
grep -qF "$CANARY" "$LEDGER" 2>/dev/null && LEAK=1
grep -rqF "$CANARY" "$RUNS_DIR" 2>/dev/null && LEAK=1
if [ "$LEAK" -eq 0 ]; then
    pass "the canary key reached no stdout, stderr, worktree/logs file, ledger or runs dir"
else
    fail "the canary key leaked into an output, log, ledger or runs dir"
fi

echo
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: check_opencode_sandbox.sh, at least one assertion failed above"
    exit 1
fi
if [ "$UNMEASURED" -ne 0 ]; then
    echo "UNMEASURED: check_opencode_sandbox.sh, at least one probe could not be measured"
    exit 2
fi
echo "PASS: check_opencode_sandbox.sh"
exit 0
