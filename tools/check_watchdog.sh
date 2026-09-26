#!/bin/bash
# gate: cheap
#
# Does tools/watchdog.sh stop a command whose output never starts or stops
# growing, killing the whole process group (grandchildren included), leave a
# healthy run alone, pass through the command's own exit code, wire --in to
# the command's stdin, validate its limits, and make tools/codex_exec.sh use
# it? Defends bead inc-gofz: a stalled implementer run must be stopped rather
# than hang its dispatcher forever.
#
# Fully offline. Stub commands written into a temp dir stand in for the
# harnesses; limits of 1-3 seconds via INCURSION_WATCHDOG_* keep the whole
# check quick. No network request ever leaves this machine.
#
#   tools/check_watchdog.sh               run the nine assertions
#   tools/check_watchdog.sh --prove-red   neuter the watchdog's kill, confirm
#                                         assertions a and b go red, restore
#
# Exit: 0 pass, 1 fail, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WATCHDOG="$ROOT/tools/watchdog.sh"
CODEX="$ROOT/tools/codex_exec.sh"

TMP="$(mktemp -d)" || exit 2
BACKUP=""
SAFETY_PIDS=""

cleanup() {
    # Kill any stub the safety net started and could not reap.
    if [ -n "$SAFETY_PIDS" ]; then
        for p in $SAFETY_PIDS; do kill -KILL "$p" 2>/dev/null; done
    fi
    if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$WATCHDOG"
        if cmp -s "$BACKUP" "$WATCHDOG"; then
            echo "restored tools/watchdog.sh byte-identical to its original"
        else
            echo "COULD NOT CONFIRM tools/watchdog.sh WAS RESTORED -- check it by hand" >&2
        fi
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

FAIL=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }

# --- --prove-red ----------------------------------------------------------
# Handled FIRST, before the assertions below run. Neutralise the kill in
# stop_run: with the TERM/KILL disabled and the exit 124 replaced by a no-op
# the watchdog never stops the command, so assertions a (startup) and b (idle)
# must go red. The original is restored, and verified byte-identical with cmp,
# by the EXIT trap above.
if [ "${1:-}" = "--prove-red" ]; then
    PROVE_FAIL=0
    BACKUP="$TMP/watchdog.sh.orig"
    cp "$WATCHDOG" "$BACKUP"

    TERM_NEEDLE='    kill -TERM -- "-$PGID" 2>/dev/null'
    KILL_NEEDLE='        kill -KILL -- "-$PGID" 2>/dev/null'
    EXIT_NEEDLE='    exit 124'
    for needle in "$TERM_NEEDLE" "$KILL_NEEDLE" "$EXIT_NEEDLE"; do
        if ! grep -qF "$needle" "$WATCHDOG"; then
            echo "could not find the watchdog kill to mutate: $needle" >&2
            exit 2
        fi
    done
    python3 - "$WATCHDOG" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('    kill -TERM -- "-$PGID" 2>/dev/null',
                  '    : # MUTATED by --prove-red', 1)
src = src.replace('        kill -KILL -- "-$PGID" 2>/dev/null',
                  '        : # MUTATED by --prove-red', 1)
src = src.replace('    exit 124', '    : # MUTATED by --prove-red', 1)
open(path, "w").write(src)
PY
    echo "mutated tools/watchdog.sh: stop_run's kill and exit 124 disabled"

    MUT_OUT="$("$ROOT/tools/check_watchdog.sh" 2>&1)"
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ] && grep -q "FAIL.*startup" <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion a (startup) went red"
    else
        echo "FAIL: assertion a stayed green under a disabled stop (rc=$MUT_RC)"
        echo "$MUT_OUT" | tail -20
        PROVE_FAIL=1
    fi
    if [ "$MUT_RC" -ne 0 ] && grep -q "FAIL.*idle" <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion b (idle) went red"
    else
        echo "FAIL: assertion b stayed green under a disabled stop (rc=$MUT_RC)"
        echo "$MUT_OUT" | tail -20
        PROVE_FAIL=1
    fi

    cp "$BACKUP" "$WATCHDOG"
    cmp -s "$BACKUP" "$WATCHDOG" || { echo "restore of watchdog.sh failed" >&2; exit 2; }

    if [ "$PROVE_FAIL" -eq 0 ]; then
        echo "PASS: --prove-red, neutering the stop turned assertions a and b red"
        exit 0
    fi
    exit 1
fi

# --- stub fixtures --------------------------------------------------------
# One stub script, mode selected by STUB_MODE. It records its own pid (and, in
# never mode, its background grandchild's) so the check can confirm the whole
# process group died. Never mode writes NOTHING to stdout, so --out stays 0.
STUB="$TMP/stub"
cat > "$STUB" <<'STUB_EOF'
#!/bin/bash
MODE="${STUB_MODE:-exit3}"
if [ -n "${STUB_SELF_PID:-}" ]; then
    printf '%s\n' "$$" > "$STUB_SELF_PID"
fi
case "$MODE" in
    never)
        sleep 1000 &
        if [ -n "${STUB_GRAND_PID:-}" ]; then
            printf '%s\n' "$!" > "$STUB_GRAND_PID"
        fi
        sleep 1000
        ;;
    stubborn)
        bash -c 'trap "" TERM; sleep 1000' &
        if [ -n "${STUB_GRAND_PID:-}" ]; then
            printf '%s\n' "$!" > "$STUB_GRAND_PID"
        fi
        sleep 1000
        ;;
    oneline)
        echo "one line of output"
        sleep 1000
        ;;
    progress)
        for i in 1 2 3 4; do
            echo "tick $i"
            sleep 1
        done
        exit 0
        ;;
    exit3)
        exit 3
        ;;
    stdin)
        cat > "${STUB_STDIN_OUT:-/dev/null}"
        echo "read stdin"
        exit 0
        ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB"

# run_bounded <safety-seconds> <out> <err> <status> [extra env assignments...]
#   -- <command...>
# Runs the watchdog with a safety net: if the watchdog is still alive after
# <safety-seconds> the net KILLs it and every stub pid recorded in
# STUB_SELF_PID/STUB_GRAND_PID, so a red run cannot itself hang the check.
# Prints the watchdog's exit code to stdout and returns 0 always.
run_bounded() {
    local safety="$1"; shift
    local out="$1" err="$2" status="$3"; shift 3
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
        envs+=("$1"); shift
    done
    [ "${1:-}" = "--" ] && shift

    rm -f "$STUB_SELF_PID" "$STUB_GRAND_PID"
    env "${envs[@]}" "$WATCHDOG" --out "$out" --err "$err" --status "$status" -- "$@" &
    local wdpid=$!
    (
        sleep "$safety"
        if kill -0 "$wdpid" 2>/dev/null; then
            kill -KILL "$wdpid" 2>/dev/null
            for f in "$STUB_SELF_PID" "$STUB_GRAND_PID"; do
                if [ -f "$f" ]; then kill -KILL "$(cat "$f")" 2>/dev/null; fi
            done
        fi
    ) &
    local safetypid=$!
    wait "$wdpid"
    local rc=$?
    kill "$safetypid" 2>/dev/null
    wait "$safetypid" 2>/dev/null
    printf '%s\n' "$rc"
    return 0
}

pid_dead() {
    kill -0 "$1" 2>/dev/null && return 1
    return 0
}

# --- a. startup: a run that never writes is stopped, group and all ---------
OUT="$TMP/a.out"; ERR="$TMP/a.err"; STATUS="$TMP/a.status"
STUB_SELF_PID="$TMP/a.self"; STUB_GRAND_PID="$TMP/a.grand"
rm -f "$OUT" "$ERR" "$STATUS" "$STUB_SELF_PID" "$STUB_GRAND_PID"
RC="$(run_bounded 8 "$OUT" "$ERR" "$STATUS" \
    STUB_MODE=never STUB_SELF_PID="$STUB_SELF_PID" STUB_GRAND_PID="$STUB_GRAND_PID" \
    INCURSION_WATCHDOG_STARTUP=2 INCURSION_WATCHDOG_POLL=1 INCURSION_WATCHDOG_GRACE=2 \
    -- "$STUB")"
CHILD_PID="$(cat "$STUB_SELF_PID" 2>/dev/null)"
GRAND_PID="$(cat "$STUB_GRAND_PID" 2>/dev/null)"
sleep 1
if [ "$RC" -eq 124 ] && [ "$(cat "$STATUS" 2>/dev/null)" = "startup" ] \
    && [ -n "$CHILD_PID" ] && pid_dead "$CHILD_PID" \
    && [ -n "$GRAND_PID" ] && pid_dead "$GRAND_PID"; then
    pass "startup: no output stopped, status startup, child and grandchild dead"
else
    fail "startup: rc=$RC status=$(cat "$STATUS" 2>/dev/null) child=$CHILD_PID grand=$GRAND_PID out=$(wc -c < "$OUT" 2>/dev/null)"
fi

# --- a2. a TERM-ignoring grandchild dies with the group -------------------
# The leader exits on TERM but its grandchild TRAPs and ignores TERM; only the
# KILL to the whole group reaches it. Defends the group-wait stop_run: waiting
# on the leader alone would leave this grandchild alive.
OUT="$TMP/a2.out"; ERR="$TMP/a2.err"; STATUS="$TMP/a2.status"
STUB_SELF_PID="$TMP/a2.self"; STUB_GRAND_PID="$TMP/a2.grand"
rm -f "$OUT" "$ERR" "$STATUS" "$STUB_SELF_PID" "$STUB_GRAND_PID"
RC="$(run_bounded 8 "$OUT" "$ERR" "$STATUS" \
    STUB_MODE=stubborn STUB_SELF_PID="$STUB_SELF_PID" STUB_GRAND_PID="$STUB_GRAND_PID" \
    INCURSION_WATCHDOG_STARTUP=2 INCURSION_WATCHDOG_POLL=1 INCURSION_WATCHDOG_GRACE=2 \
    -- "$STUB")"
GRAND_PID="$(cat "$STUB_GRAND_PID" 2>/dev/null)"
sleep 1
if [ "$RC" -eq 124 ] && [ -n "$GRAND_PID" ] && pid_dead "$GRAND_PID"; then
    pass "stubborn grandchild: exit 124, TERM-ignoring grandchild dead"
else
    fail "stubborn grandchild: rc=$RC grand=$GRAND_PID status=$(cat "$STATUS" 2>/dev/null)"
fi

# --- b. idle: a run that stops growing is stopped -------------------------
OUT="$TMP/b.out"; ERR="$TMP/b.err"; STATUS="$TMP/b.status"
STUB_SELF_PID="$TMP/b.self"; STUB_GRAND_PID="$TMP/b.grand"
rm -f "$OUT" "$ERR" "$STATUS"
RC="$(run_bounded 8 "$OUT" "$ERR" "$STATUS" \
    STUB_MODE=oneline STUB_SELF_PID="$STUB_SELF_PID" STUB_GRAND_PID="$STUB_GRAND_PID" \
    INCURSION_WATCHDOG_STARTUP=2 INCURSION_WATCHDOG_IDLE=2 INCURSION_WATCHDOG_POLL=1 \
    INCURSION_WATCHDOG_GRACE=2 \
    -- "$STUB")"
if [ "$RC" -eq 124 ] && [ "$(cat "$STATUS" 2>/dev/null)" = "idle" ]; then
    pass "idle: output stopped growing, status idle, exit 124"
else
    fail "idle: rc=$RC status=$(cat "$STATUS" 2>/dev/null) out=$(cat "$OUT" 2>/dev/null)"
fi

# --- c. a steadily writing run is NOT stopped -----------------------------
OUT="$TMP/c.out"; ERR="$TMP/c.err"; STATUS="$TMP/c.status"
rm -f "$OUT" "$ERR" "$STATUS"
RC="$(run_bounded 8 "$OUT" "$ERR" "$STATUS" \
    STUB_MODE=progress STUB_SELF_PID="$TMP/c.self" STUB_GRAND_PID="$TMP/c.grand" \
    INCURSION_WATCHDOG_STARTUP=3 INCURSION_WATCHDOG_IDLE=3 INCURSION_WATCHDOG_POLL=1 \
    INCURSION_WATCHDOG_GRACE=2 \
    -- "$STUB")"
if [ "$RC" -eq 0 ] && [ ! -f "$STATUS" ]; then
    pass "progress: steady writes exit 0, no status file"
else
    fail "progress: rc=$RC status-exists=$([ -f "$STATUS" ] && echo yes || echo no)"
fi

# --- d. the command's own exit code passes through ------------------------
OUT="$TMP/d.out"; ERR="$TMP/d.err"; STATUS="$TMP/d.status"
rm -f "$OUT" "$ERR" "$STATUS"
RC="$(run_bounded 8 "$OUT" "$ERR" "$STATUS" \
    STUB_MODE=exit3 STUB_SELF_PID="$TMP/d.self" STUB_GRAND_PID="$TMP/d.grand" \
    INCURSION_WATCHDOG_STARTUP=2 INCURSION_WATCHDOG_POLL=1 \
    -- "$STUB")"
if [ "$RC" -eq 3 ]; then
    pass "passthrough: command's exit 3 becomes the watchdog's exit 3"
else
    fail "passthrough: rc=$RC (wanted 3)"
fi

# --- e. --in reaches the command's stdin ----------------------------------
OUT="$TMP/e.out"; ERR="$TMP/e.err"; STATUS="$TMP/e.status"; STDIN_OUT="$TMP/e.stdin"
rm -f "$OUT" "$ERR" "$STATUS" "$STDIN_OUT"
BRIEF="$TMP/e.brief"; printf 'the brief text\n' > "$BRIEF"
"$WATCHDOG" --in "$BRIEF" --out "$OUT" --err "$ERR" --status "$STATUS" -- \
    env STUB_MODE=stdin STUB_STDIN_OUT="$STDIN_OUT" STUB_SELF_PID="$TMP/e.self" \
    STUB_GRAND_PID="$TMP/e.grand" INCURSION_WATCHDOG_STARTUP=3 "$STUB" >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ] && grep -q 'the brief text' "$STDIN_OUT" 2>/dev/null; then
    pass "--in: the command's stdin carried the file"
else
    fail "--in: rc=$RC stdin-out=$(cat "$STDIN_OUT" 2>/dev/null)"
fi

# --- f. codex_exec.sh drives the watchdog and passes the brief on stdin ----
# A well-behaved fake codex records its argv and stdin, writes a line so the
# watchdog sees progress, and exits 0.
FAKE_CODEX="$TMP/fake-codex"
cat > "$FAKE_CODEX" <<'FAKE_EOF'
#!/bin/bash
REC="${FAKE_REC:-/dev/null}"
{
    for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$REC"
cat >> "${FAKE_STDIN:-/dev/null}"
echo "fake codex ran"
exit "${FAKE_RC:-0}"
FAKE_EOF
chmod +x "$FAKE_CODEX"

WT="$TMP/wt-f"; mkdir -p "$WT"
WT_RESOLVED="$(cd "$WT" && pwd -P)"
BRIEF="$TMP/f.brief"; printf 'the codex brief\n' > "$BRIEF"
REC="$TMP/f.rec"; STDIN_FILE="$TMP/f.stdin"
rm -f "$REC" "$STDIN_FILE"
RC="$(INCURSION_CODEX_BIN="$FAKE_CODEX" FAKE_REC="$REC" FAKE_STDIN="$STDIN_FILE" \
    "$CODEX" "$WT" "$BRIEF" > "$TMP/f.out" 2> "$TMP/f.err"; echo $?)"
RUNDIR="$(ls -d "$WT"/logs/codex/* 2>/dev/null | head -n 1)"
if [ "$RC" -eq 0 ] \
    && grep -q '^ARG exec$' "$REC" 2>/dev/null \
    && grep -q '^ARG --json$' "$REC" 2>/dev/null \
    && grep -q "^ARG -C$" "$REC" 2>/dev/null \
    && grep -q "^ARG $WT_RESOLVED$" "$REC" 2>/dev/null \
    && grep -q '^ARG -s$' "$REC" 2>/dev/null \
    && grep -q '^ARG workspace-write$' "$REC" 2>/dev/null \
    && grep -q '^ARG -o$' "$REC" 2>/dev/null \
    && grep -q '^ARG -$' "$REC" 2>/dev/null \
    && grep -q 'the codex brief' "$STDIN_FILE" 2>/dev/null; then
    pass "codex_exec: argv exec --json -C -s workspace-write -o ... -, brief on stdin, exit 0"
else
    fail "codex_exec well-behaved: rc=$RC rec=$(cat "$REC" 2>/dev/null) stdin=$(cat "$STDIN_FILE" 2>/dev/null) -- $(cat "$TMP/f.err")"
fi

# A fake that never writes must make the wrapper exit 2 naming startup.
FAKE_SILENT="$TMP/fake-silent"
cat > "$FAKE_SILENT" <<'SILENT_EOF'
#!/bin/bash
sleep 1000
SILENT_EOF
chmod +x "$FAKE_SILENT"
WT="$TMP/wt-f2"; mkdir -p "$WT"
BRIEF="$TMP/f2.brief"; printf 'the codex brief\n' > "$BRIEF"
RC="$(INCURSION_CODEX_BIN="$FAKE_SILENT" INCURSION_WATCHDOG_STARTUP=2 \
    INCURSION_WATCHDOG_POLL=1 INCURSION_WATCHDOG_GRACE=2 \
    "$CODEX" "$WT" "$BRIEF" > "$TMP/f2.out" 2> "$TMP/f2.err"; echo $?)"
if [ "$RC" -eq 2 ] && grep -q 'startup' "$TMP/f2.err"; then
    pass "codex_exec: a never-writing codex exits 2 naming startup"
else
    fail "codex_exec silent: rc=$RC err=$(cat "$TMP/f2.err")"
fi

# --- g. a bad limit value fails closed ------------------------------------
OUT="$TMP/g.out"; ERR="$TMP/g.err"; STATUS="$TMP/g.status"
rm -f "$OUT" "$ERR" "$STATUS"
INCURSION_WATCHDOG_IDLE=abc "$WATCHDOG" --out "$OUT" --err "$ERR" --status "$STATUS" -- true \
    >/dev/null 2> "$TMP/g.err"
RC=$?
if [ "$RC" -eq 2 ] && grep -q 'INCURSION_WATCHDOG_IDLE' "$TMP/g.err"; then
    pass "bad env: INCURSION_WATCHDOG_IDLE=abc exits 2 naming the variable"
else
    fail "bad env: rc=$RC err=$(cat "$TMP/g.err")"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: check_watchdog.sh, all nine assertions"
    exit 0
else
    echo "FAIL: check_watchdog.sh, at least one assertion failed above"
    exit 1
fi
