#!/bin/bash
# gate: cheap
# gate-serial: starts a stub on a fixed 127.0.0.1 loopback URL; parallel network timing could flip it
#
# Does tools/deepseek.py spend at most one billed call per success, resolve its
# default ledger to the MAIN checkout so every worktree shares one ledger, and
# never let the DeepInfra key reach stdout, stderr or the ledger? Defends bead
# inc-3dgz: a scoped DeepSeek client. The ledger records every run's cost but
# never refuses a run (owner ruling, 2026-10-04).
#
# Fully offline. tools/deepseek_stub.py stands in for api.deepinfra.com;
# INCURSION_DEEPSEEK_URL points the client at it, and this check kills the
# stub in a trap. No network request ever leaves this machine.
#
#   tools/check_deepseek.sh               run the assertions
#
# Exit: 0 pass, 1 fail, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEEPSEEK="$ROOT/tools/deepseek.py"
STUB="$ROOT/tools/deepseek_stub.py"

TMP="$(mktemp -d)" || exit 2
STUB_PID=""
BACKUP=""

cleanup() {
    if [ -n "$STUB_PID" ]; then
        kill "$STUB_PID" 2>/dev/null
        wait "$STUB_PID" 2>/dev/null
    fi
    if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$DEEPSEEK"
        if cmp -s "$BACKUP" "$DEEPSEEK"; then
            echo "restored tools/deepseek.py byte-identical to its original"
        else
            echo "COULD NOT CONFIRM tools/deepseek.py WAS RESTORED -- check it by hand" >&2
        fi
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

FAIL=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }

# Starts (or restarts) the stub in the given mode and points
# INCURSION_DEEPSEEK_URL at it. Resets the request-count file to "0".
start_stub() {
    local mode="$1"
    if [ -n "$STUB_PID" ]; then
        kill "$STUB_PID" 2>/dev/null
        wait "$STUB_PID" 2>/dev/null
        STUB_PID=""
    fi
    printf '0' > "$TMP/count"
    INCURSION_STUB_MODE="$mode" INCURSION_STUB_COUNT="$TMP/count" \
        python3 "$STUB" > "$TMP/stub.port" 2>"$TMP/stub.err" &
    STUB_PID=$!

    local port=""
    for _ in $(seq 1 50); do
        port="$(head -n1 "$TMP/stub.port" 2>/dev/null)"
        [ -n "$port" ] && break
        sleep 0.1
    done
    if [ -z "$port" ]; then
        echo "the stub never printed a port" >&2
        cat "$TMP/stub.err" >&2
        exit 2
    fi
    export INCURSION_DEEPSEEK_URL="http://127.0.0.1:${port}/v1/openai/chat/completions"
}

req_count() { cat "$TMP/count" 2>/dev/null; }

# --- --prove-red ----------------------------------------------------------
# (removed 2026-10-04: the budget guard it mutated no longer exists)

PROMPT="$TMP/prompt.txt"
echo "hello" > "$PROMPT"

# --- 1. Happy path ------------------------------------------------------
start_stub ok
LEDGER="$TMP/ledger1.jsonl"; : > "$LEDGER"
OUT="$TMP/out1.txt"
OUTPUT="$(INCURSION_DEEPSEEK_KEY=test-key INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$DEEPSEEK" --prompt "$PROMPT" --out "$OUT" 2>&1)"
RC=$?
if [ "$RC" -eq 0 ] \
    && [ -f "$OUT" ] && grep -qF "STUB REPLY OK" "$OUT" \
    && [ "$(wc -l < "$LEDGER" | tr -d ' ')" -eq 1 ] \
    && grep -q '"cost":0.000123' "$LEDGER" \
    && grep -q '"cached_tokens":7' "$LEDGER"; then
    pass "happy path: exit 0, output written, ledger gains one correct row"
else
    fail "happy path: rc=$RC output=$OUTPUT ledger=$(cat "$LEDGER" 2>/dev/null)"
fi

# --- 4. A malformed ledger line is a hard error -------------------------
start_stub ok
LEDGER="$TMP/ledger4.jsonl"
printf 'not json\n' > "$LEDGER"
OUT="$TMP/out4.txt"
OUTPUT="$(INCURSION_DEEPSEEK_KEY=test-key INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$DEEPSEEK" --prompt "$PROMPT" --out "$OUT" 2>&1)"
RC=$?
if [ "$RC" -eq 2 ] && [ "$(req_count)" = "0" ]; then
    pass "malformed ledger line is a hard error: exit 2, no request"
else
    fail "malformed ledger: rc=$RC requests=$(req_count) -- $OUTPUT"
fi

# --- 5. An unknown price poisons the ledger ------------------------------
start_stub no-cost
LEDGER="$TMP/ledger5.jsonl"; : > "$LEDGER"
OUT="$TMP/out5.txt"
OUTPUT="$(INCURSION_DEEPSEEK_KEY=test-key INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$DEEPSEEK" --prompt "$PROMPT" --out "$OUT" 2>&1)"
RC=$?
if [ "$RC" -eq 2 ] \
    && [ "$(wc -l < "$LEDGER" | tr -d ' ')" -eq 1 ] \
    && grep -q '"cost":null' "$LEDGER" \
    && [ -f "$OUT" ]; then
    pass "missing estimated_cost poisons the ledger: exit 2, null row, output kept"
else
    fail "unknown price: rc=$RC ledger=$(cat "$LEDGER" 2>/dev/null) out-exists=$([ -f "$OUT" ] && echo yes || echo no) -- $OUTPUT"
fi

# --- 6. An HTTP failure bills nothing ------------------------------------
start_stub error
LEDGER="$TMP/ledger6.jsonl"; : > "$LEDGER"
OUT="$TMP/out6.txt"
OUTPUT="$(INCURSION_DEEPSEEK_KEY=test-key INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$DEEPSEEK" --prompt "$PROMPT" --out "$OUT" 2>&1)"
RC=$?
if [ "$RC" -eq 2 ] && [ ! -s "$LEDGER" ] && [ ! -e "$OUT" ]; then
    pass "HTTP failure bills nothing: exit 2, no ledger row, no output"
else
    fail "HTTP failure: rc=$RC ledger=$(cat "$LEDGER" 2>/dev/null) out-exists=$([ -e "$OUT" ] && echo yes || echo no) -- $OUTPUT"
fi

# --- 7. The key never leaks ----------------------------------------------
start_stub ok
CANARY="canary-do-not-print-7f3a"
LEDGER="$TMP/ledger7.jsonl"; : > "$LEDGER"
OUT="$TMP/out7.txt"
OUTPUT="$(INCURSION_DEEPSEEK_KEY="$CANARY" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$DEEPSEEK" --prompt "$PROMPT" --out "$OUT" 2>&1)"
LEAK_LIVE=0
grep -qF "$CANARY" <<< "$OUTPUT" && LEAK_LIVE=1
grep -qF "$CANARY" "$LEDGER" && LEAK_LIVE=1

DRYOUT="$(INCURSION_DEEPSEEK_KEY="$CANARY" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$DEEPSEEK" --prompt "$PROMPT" --out "$TMP/out7dry.txt" --dry-run 2>&1)"
LEAK_DRY=0
grep -qF "$CANARY" <<< "$DRYOUT" && LEAK_DRY=1

if [ "$LEAK_LIVE" -eq 0 ] && [ "$LEAK_DRY" -eq 0 ]; then
    pass "the key never appears in stdout, stderr or the ledger (live and --dry-run)"
else
    fail "the key leaked: live-leak=$LEAK_LIVE dry-run-leak=$LEAK_DRY"
fi

# --- 8. The default ledger lives in the main checkout --------------------
# A per-worktree ledger would let each worktree's budget check see only its
# own spend, and the spend would vanish with the worktree. Prove that
# resolve_ledger_path() from a linked worktree finds the MAIN checkout's
# logs/deepseek-ledger.jsonl. This builds its own throwaway repo under $TMP:
# git here is the check's, never the project repo, and nothing leaves the
# machine. The env override is unset so the git-derived default is exercised.
MAIN_REPO="$(cd "$TMP" && pwd -P)/main"
WT_REPO="$(cd "$TMP" && pwd -P)/wt"
git init -q "$MAIN_REPO" 2>/dev/null
git -C "$MAIN_REPO" -c user.email=check@example.com -c user.name=check \
    commit -q --allow-empty -m init 2>/dev/null
git -C "$MAIN_REPO" worktree add -q "$WT_REPO" 2>/dev/null
mkdir -p "$MAIN_REPO/tools" "$WT_REPO/tools"
cp -f "$DEEPSEEK" "$MAIN_REPO/tools/deepseek.py"
cp -f "$DEEPSEEK" "$WT_REPO/tools/deepseek.py"
RESOLVED="$(env -u INCURSION_DEEPSEEK_LEDGER python3 - "$WT_REPO/tools/deepseek.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("deepseek", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
sys.stdout.write(str(mod.resolve_ledger_path()))
PY
)"
EXPECTED="$MAIN_REPO/logs/deepseek-ledger.jsonl"
if [ -n "$RESOLVED" ] && [ "$RESOLVED" = "$EXPECTED" ]; then
    pass "default ledger resolves to the main checkout from a linked worktree"
else
    fail "default ledger: from worktree resolved '$RESOLVED', expected '$EXPECTED'"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: check_deepseek.sh, all assertions"
    exit 0
else
    echo "FAIL: check_deepseek.sh, at least one assertion failed above"
    exit 1
fi
