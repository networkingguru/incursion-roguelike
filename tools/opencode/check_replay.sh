#!/bin/bash
# gate: cheap
# gate-serial: starts a stub on a fixed 127.0.0.1 loopback URL; parallel network timing could flip it
#
# Does tools/opencode/replay.py replay one captured request correctly and
# safely? Defends bead inc-w431: a measuring tool that re-sends a captured
# chat-completions request N times, changes only the top-level fields it was
# told to, saves every streamed reply, and records every call's cost in the
# shared ledger (poisoning it by design when a price is unknown).
#
# Fully offline. tools/opencode/replay_stub.py stands in for DeepInfra;
# INCURSION_DEEPSEEK_URL points replay.py at it and this check kills the stub
# in a trap. No network request ever leaves this machine.
#
#   tools/opencode/check_replay.sh               run the assertions
#   tools/opencode/check_replay.sh --prove-red   mutate replay.py's markup_leak
#                                                and confirm the check goes red
#
# Exit: 0 pass, 1 fail, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPLAY="$ROOT/tools/opencode/replay.py"
STUB="$ROOT/tools/opencode/replay_stub.py"

TMP="$(mktemp -d)" || exit 2
STUB_PID=""
BACKUP=""

cleanup() {
    if [ -n "$STUB_PID" ]; then
        kill "$STUB_PID" 2>/dev/null
        wait "$STUB_PID" 2>/dev/null
    fi
    if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
        cp -f "$BACKUP" "$REPLAY"
        if cmp -s "$BACKUP" "$REPLAY"; then
            echo "restored tools/opencode/replay.py byte-identical to its original"
        else
            echo "COULD NOT CONFIRM tools/opencode/replay.py WAS RESTORED -- check it by hand" >&2
        fi
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

FAIL=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }

start_stub() {
    local mode="$1"
    if [ -n "$STUB_PID" ]; then
        kill "$STUB_PID" 2>/dev/null
        wait "$STUB_PID" 2>/dev/null
        STUB_PID=""
    fi
    printf '0' > "$TMP/count"
    INCURSION_REPLAY_MODE="$mode" INCURSION_REPLAY_COUNT="$TMP/count" \
        INCURSION_REPLAY_SAVE="$TMP" \
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
# Handled FIRST. Applies each mutation below to tools/opencode/replay.py in
# turn, re-runs THIS script (fresh stub, fresh tmp dir) against the mutated
# file, and expects that run to fail. Every mutation is reverted immediately
# after its run and the EXIT trap restores the original anyway, verifying it
# byte-identical with cmp.
#
#   markup_leak   forced false, so a DSML stream is never flagged (test 2)
#   cached term   dropped from the price computation, so test 8's cost is
#                 wrong (it would omit the cached-token product)
run_prove_red() {
    local label="$1" needle="$2" repl="$3"
    BACKUP="$TMP/replay.py.orig"
    cp -f "$REPLAY" "$BACKUP"

    if ! grep -qF "$needle" "$REPLAY"; then
        echo "could not find the site to mutate ($label): $needle" >&2
        return 2
    fi
    python3 - "$REPLAY" "$needle" "$repl" <<'PY'
import sys
path, needle, repl = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
open(path, "w").write(src.replace(needle, repl, 1))
PY
    echo "mutated tools/opencode/replay.py ($label)"

    MUTATED_OUTPUT="$("$ROOT/tools/opencode/check_replay.sh")"
    MUTATED_RC=$?
    echo "--- output of the mutated run ($label) ---"
    echo "$MUTATED_OUTPUT"
    echo "--- end output of the mutated run ($label) ---"

    cp -f "$BACKUP" "$REPLAY"
    BACKUP=""

    if [ "$MUTATED_RC" -ne 0 ]; then
        echo "PASS (as intended): check_replay.sh went red under the $label mutation, rc=$MUTATED_RC"
        return 0
    else
        echo "FAIL: check_replay.sh stayed green under the $label mutation"
        return 1
    fi
}

if [ "${1:-}" = "--prove-red" ]; then
    RED_RC=0
    run_prove_red "markup_leak" \
        'leaked = markup_leak(content, reasoning)' \
        'leaked = False  # MUTATED by --prove-red' || RED_RC=1
    run_prove_red "cached term" \
        '+ (cached_tokens or 0) * args.price_cached' \
        '# MUTATED by --prove-red: cached term dropped' || RED_RC=1
    exit "$RED_RC"
fi

# A small captured request fixture: one system + one user message, stream on.
CAPTURE="$TMP/capture.request.json"
python3 - "$CAPTURE" <<'PY'
import json, sys
body = {
    "model": "deepseek-ai/DeepSeek-V4.1-Flash",
    "max_tokens": 32000,
    "messages": [
        {"role": "system", "content": "You are a test fixture."},
        {"role": "user", "content": "say hello"},
    ],
    "stream": True,
    "stream_options": {"include_usage": True},
}
open(sys.argv[1], "w").write(json.dumps(body))
PY

REPLAY_ENV=(env INCURSION_DEEPSEEK_KEY=dummy)

# --- 1. Happy path: files + one ledger row ------------------------------
start_stub ok
LEDGER="$TMP/ledger1.jsonl"; : > "$LEDGER"
OUT="$TMP/out1"
OUTPUT="$("${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" 2>&1)"
RC=$?
if [ "$RC" -eq 0 ] \
    && [ -s "$OUT/run-01.response.txt" ] \
    && [ -s "$OUT/run-01.content.txt" ] \
    && [ -s "$OUT/run-01.summary.json" ] \
    && [ "$(grep -c '' "$LEDGER" 2>/dev/null)" -eq 1 ] \
    && grep -q '"cost":0.000123' "$LEDGER" \
    && grep -q '"harness":"replay"' "$LEDGER" \
    && grep -q '"cached_tokens":7' "$LEDGER" \
    && grep -q '"model":"deepseek-ai/DeepSeek-V4.1-Flash"' "$LEDGER"; then
    pass "happy path: exit 0, response/content/summary written, one correct ledger row"
else
    fail "happy path: rc=$RC -- $OUTPUT -- ledger=$(cat "$LEDGER" 2>/dev/null)"
fi

# --- 2. markup_leak true when DSML is present ---------------------------
start_stub markup
LEDGER="$TMP/ledger2.jsonl"; : > "$LEDGER"
OUT="$TMP/out2"
OUTPUT="$("${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" 2>&1)"
if [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["markup_leak"])' "$OUT/run-01.summary.json" 2>/dev/null)" = "True" ]; then
    pass "markup_leak true when content contains DSML"
else
    fail "markup_leak should be true for a DSML stream -- $OUTPUT"
fi

# --- 3. markup_leak false for a clean stream ----------------------------
start_stub ok
LEDGER="$TMP/ledger3.jsonl"; : > "$LEDGER"
OUT="$TMP/out3"
"${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" >/dev/null 2>&1
if [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["markup_leak"])' "$OUT/run-01.summary.json" 2>/dev/null)" = "False" ]; then
    pass "markup_leak false for a clean stream"
else
    fail "markup_leak should be false for a clean stream"
fi

# --- 3b. markup_leak false when the token is quoted mid-line ------------
# A real leak puts the markup at a line start; a model that merely quotes it
# inline, e.g. inside backticks, is prose, not a leak.
start_stub markup-inline
LEDGER="$TMP/ledger3b.jsonl"; : > "$LEDGER"
OUT="$TMP/out3b"
"${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" >/dev/null 2>&1
if [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["markup_leak"])' "$OUT/run-01.summary.json" 2>/dev/null)" = "False" ]; then
    pass "markup_leak false when the token is quoted mid-line in backticks"
else
    fail "markup_leak should be false for an inline-backtick mention"
fi

# --- 4. top_line_repeats counts 40 repeated lines -----------------------
start_stub repeat
LEDGER="$TMP/ledger4.jsonl"; : > "$LEDGER"
OUT="$TMP/out4"
"${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" >/dev/null 2>&1
REPEATS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["top_line_repeats"])' "$OUT/run-01.summary.json" 2>/dev/null)"
if [ "$REPEATS" = "40" ]; then
    pass "top_line_repeats is 40 for a line repeated 40 times"
else
    fail "top_line_repeats: got '$REPEATS', expected 40"
fi

# --- 5. --set changes only the named top-level field --------------------
start_stub ok
LEDGER="$TMP/ledger5.jsonl"; : > "$LEDGER"
OUT="$TMP/out5"
rm -f "$TMP"/request-*.json
"${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" \
    --set repetition_penalty=1.15 >/dev/null 2>&1
SENT="$TMP/request-1.json"
if [ -f "$SENT" ] && python3 - "$CAPTURE" "$SENT" <<'PY'
import json, sys
captured = json.load(open(sys.argv[1]))
sent = json.load(open(sys.argv[2]))
assert sent.get("repetition_penalty") == 1.15, "repetition_penalty not set"
for key, value in captured.items():
    assert key in sent, "field %r was dropped" % key
    assert sent[key] == value, "field %r changed" % key
extra = set(sent) - set(captured) - {"repetition_penalty"}
assert not extra, "unexpected fields added: %r" % extra
PY
then
    pass "--set repetition_penalty=1.15 reaches the body, every other field unchanged"
else
    fail "--set assertion failed; sent body: $(cat "$SENT" 2>/dev/null | head -c 300)"
fi

# --- 6. a ledger over the old cap no longer refuses the POST -------------
# The budget cap was removed (owner ruling, 2026-10-04): a ledger whose sum
# exceeds it must not block the call. The stub sees the POST and a row lands.
start_stub ok
LEDGER="$TMP/ledger6.jsonl"
printf '%s\n' '{"cost": 25.00}' > "$LEDGER"
OUT="$TMP/out6"
OUTPUT="$("${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" 2>&1)"
RC=$?
if [ "$RC" -eq 0 ] && [ "$(req_count)" = "1" ] \
    && [ "$(grep -c '' "$LEDGER")" -eq 2 ]; then
    pass "ledger over the old cap still spends: exit 0, server saw the POST, row appended"
else
    fail "over-cap spend: rc=$RC requests=$(req_count) -- $OUTPUT"
fi

# --- 7. a stream with no usage poisons the ledger and exits 2 -----------
start_stub no-usage
LEDGER="$TMP/ledger7.jsonl"; : > "$LEDGER"
OUT="$TMP/out7"
OUTPUT="$("${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" 2>&1)"
RC=$?
if [ "$RC" -eq 2 ] \
    && [ "$(grep -c '' "$LEDGER" 2>/dev/null)" -eq 1 ] \
    && grep -q '"cost":null' "$LEDGER"; then
    pass "missing usage writes a cost:null row and exits 2"
else
    fail "no-usage: rc=$RC ledger=$(cat "$LEDGER" 2>/dev/null) -- $OUTPUT"
fi

# --- 8. no-cost usage with prices computes the cost and exits 0 ---------
# Fireworks streamed usage has token counts but no estimated_cost. With the
# three prices the cost is (33-5)*0.22 + 5*0.01 + 20*0.66 = 19.41 per 1e6,
# i.e. 1.941e-05, tagged cost_source=price-flags.
start_stub no-cost
LEDGER="$TMP/ledger8.jsonl"; : > "$LEDGER"
OUT="$TMP/out8"
OUTPUT="$("${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" \
    --price-in 0.22 --price-cached 0.01 --price-out 0.66 2>&1)"
RC=$?
if [ "$RC" -eq 0 ] \
    && [ "$(grep -c '' "$LEDGER" 2>/dev/null)" -eq 1 ] \
    && grep -q '"cost":1.941e-05' "$LEDGER" \
    && grep -q '"cost_source":"price-flags"' "$LEDGER" \
    && grep -q '"prices":\[0.22,0.01,0.66\]' "$LEDGER"; then
    pass "no-cost usage with prices computes cost 1.941e-05, price-flags, exit 0"
else
    fail "no-cost+price: rc=$RC ledger=$(cat "$LEDGER" 2>/dev/null) -- $OUTPUT"
fi

# --- 9. no-cost usage without prices stays null and exits 2 -------------
start_stub no-cost
LEDGER="$TMP/ledger9.jsonl"; : > "$LEDGER"
OUT="$TMP/out9"
OUTPUT="$("${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" 2>&1)"
RC=$?
if [ "$RC" -eq 2 ] \
    && [ "$(grep -c '' "$LEDGER" 2>/dev/null)" -eq 1 ] \
    && grep -q '"cost":null' "$LEDGER"; then
    pass "no-cost usage without prices writes a cost:null row and exits 2"
else
    fail "no-cost no-price: rc=$RC ledger=$(cat "$LEDGER" 2>/dev/null) -- $OUTPUT"
fi

# --- 10. a partial price set refuses before any POST --------------------
start_stub no-cost
LEDGER="$TMP/ledger10.jsonl"; : > "$LEDGER"
OUT="$TMP/out10"
OUTPUT="$("${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" \
    --price-in 0.22 --price-out 0.66 2>&1)"
RC=$?
if [ "$RC" -eq 2 ] && [ "$(req_count)" = "0" ] && [ ! -e "$OUT/run-01.response.txt" ]; then
    pass "partial price set exits 2 before any POST"
else
    fail "partial prices: rc=$RC requests=$(req_count) -- $OUTPUT"
fi

# --- 11. missing usage with prices still poisons (cost null, exit 2) ----
start_stub no-usage
LEDGER="$TMP/ledger11.jsonl"; : > "$LEDGER"
OUT="$TMP/out11"
OUTPUT="$("${REPLAY_ENV[@]}" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    python3 "$REPLAY" --request "$CAPTURE" --runs 1 --out-dir "$OUT" \
    --price-in 0.22 --price-cached 0.01 --price-out 0.66 2>&1)"
RC=$?
if [ "$RC" -eq 2 ] \
    && [ "$(grep -c '' "$LEDGER" 2>/dev/null)" -eq 1 ] \
    && grep -q '"cost":null' "$LEDGER"; then
    pass "missing usage with prices still writes a cost:null row and exits 2"
else
    fail "no-usage+price: rc=$RC ledger=$(cat "$LEDGER" 2>/dev/null) -- $OUTPUT"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: check_replay.sh, all assertions"
    exit 0
else
    echo "FAIL: check_replay.sh, at least one assertion failed above"
    exit 1
fi
