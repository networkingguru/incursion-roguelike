#!/bin/bash
# gate: cheap
# Does tools/dispatch_report.py count DeepSeek runs and agent dispatches over
# the right window, and does it report the implementation share the bead
# inc-xiqb cares about? It must: count only `harness: opencode` rows as runs
# and everything else as single requests; break the stopped runs out by `killed`
# reason (loop/context/idle/startup); sum cost with a null billed as zero; count
# dispatches by `allow`/`block`/`bypass`; break the allowed and bypassed ones
# out by model and label; keep blocked and `research`/`repro-design`/haiku
# dispatches OUT of the share; honour the `--since`/`--until` window; and print
# `n/a` when both the runs and the share are zero. A missing file counts as
# empty and is named.
#
# Fully offline, against a temp ledger and temp dispatch log (env overrides); it
# never touches the real files.
#
#   tools/check_dispatch_report.sh               run the cases
#   tools/check_dispatch_report.sh --prove-red   mutate the report so its window
#                                                filter counts every row,
#                                                confirm the window case goes
#                                                red, restore, verify with cmp
#
# Exit: 0 pass, 1 fail, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="$ROOT/tools/dispatch_report.py"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-report-check.XXXXXX")" || exit 2
LEDGER="$TMP/ledger.jsonl"
LOG="$TMP/dispatch-log.jsonl"
BUILD="$TMP/build.py"
BACKUP=""

cleanup() {
    if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$REPORT"
        if cmp -s "$BACKUP" "$REPORT"; then
            echo "restored tools/dispatch_report.py byte-identical to its original"
        else
            echo "COULD NOT CONFIRM tools/dispatch_report.py WAS RESTORED -- check it by hand" >&2
        fi
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

FAIL=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }

# --- --prove-red ----------------------------------------------------------
if [ "${1:-}" = "--prove-red" ]; then
    BACKUP="$TMP/dispatch_report.py.orig"
    cp "$REPORT" "$BACKUP"

    NEEDLE='    if ts is None or ts < since:'
    if ! grep -qF "$NEEDLE" "$REPORT"; then
        echo "could not find the window filter to mutate: $NEEDLE" >&2
        exit 2
    fi
    python3 - "$REPORT" "$NEEDLE" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path).read()
# Break the window filter so every row is counted regardless of ts.
mutated = src.replace(needle, "    if False:  # MUTATED by --prove-red\n"
                              + needle, 1)
open(path, "w").write(mutated)
PY
    echo "mutated tools/dispatch_report.py: window filter now counts every row"

    MUTATED_OUTPUT="$("$ROOT/tools/check_dispatch_report.sh")"
    MUTATED_RC=$?
    echo "--- output of the mutated run ---"
    echo "$MUTATED_OUTPUT"
    echo "--- end output of the mutated run ---"

    if [ "$MUTATED_RC" -ne 0 ] && grep -q 'FAIL.*window' <<< "$MUTATED_OUTPUT"; then
        echo "PASS (as intended): the window case went red under the mutation"
        exit 0
    elif [ "$MUTATED_RC" -ne 0 ]; then
        echo "FAIL: the run went red but not on a window case"
        exit 1
    else
        echo "FAIL: check_dispatch_report.sh stayed green with the window filter disabled"
        exit 1
    fi
fi

# --- fixtures -------------------------------------------------------------
# Three days of rows, each field deliberately chosen so a wrong report is a
# different number. Runs are `harness: opencode`; everything else is a request.
python3 - "$LEDGER" "$LOG" <<'PY'
import json, sys
ledger, log = sys.argv[1], sys.argv[2]

def run(ts, cost, killed=None, harness="opencode"):
    r = {"ts": ts, "harness": harness, "cost": cost, "steps": 3,
         "out": "/tmp/w/logs/opencode/" + ts.replace(":", "")}
    if killed:
        r["killed"] = killed
    return r

runs = [
    run("2026-10-01T05:00:00Z", 0.100, "loop"),
    run("2026-10-01T06:00:00Z", 0.250),
    run("2026-10-02T05:00:00Z", None, "context"),
    run("2026-10-03T05:00:00Z", 0.500),
    # Outside the window: a report that ignores --since/--until counts these.
    run("2026-09-30T05:00:00Z", 9.000, "loop"),
    run("2099-10-04T05:00:00Z", 9.000),
]
# Single requests: no harness, and a non-opencode harness. Neither is a run.
runs.append({"ts": "2026-10-01T07:00:00Z", "cost": 5.0, "steps": 1})
runs.append({"ts": "2026-10-02T07:00:00Z", "cost": None, "steps": 1,
             "harness": "replay"})
with open(ledger, "w") as fh:
    for r in runs:
        fh.write(json.dumps(r) + "\n")

def disp(ts, model, desc, decision):
    return {"ts": ts, "model": model, "description": desc, "decision": decision,
            "label": "x"}

disps = [
    ("2026-10-01T08:00:00Z", "sonnet", "research: read code", "allow"),
    ("2026-10-01T08:01:00Z", "sonnet", "fallback: run-1", "allow"),
    ("2026-10-01T08:02:00Z", "opus", "do the thing", "allow"),
    ("2026-10-01T08:03:00Z", "haiku", "quick", "allow"),
    ("2026-10-01T08:04:00Z", "sonnet", "repro-design: x", "allow"),
    ("2026-10-01T08:05:00Z", "sonnet", "do the thing", "block"),
    ("2026-10-01T08:06:00Z", "opus", "do the thing", "bypass"),
    ("2026-10-01T08:07:00Z", None, "do the thing", "allow"),
    # Outside the window.
    ("2026-09-30T08:00:00Z", "sonnet", "fallback: old", "allow"),
    ("2099-10-04T08:00:00Z", "sonnet", "fallback: new", "allow"),
]
with open(log, "w") as fh:
    for ts, model, desc, decision in disps:
        row = disp(ts, model, desc, decision)
        fh.write(json.dumps(row) + "\n")
PY

# run_report <since> <until|EMPTY> -> stdout in $TMP/out
run_report() {
    local since="$1" until="${2:-}"
    if [ -n "$until" ]; then
        INCURSION_DEEPSEEK_LEDGER="$LEDGER" INCURSION_DISPATCH_LOG="$LOG" \
            python3 "$REPORT" --since "$since" --until "$until" > "$TMP/out" 2>&1
    else
        INCURSION_DEEPSEEK_LEDGER="$LEDGER" INCURSION_DISPATCH_LOG="$LOG" \
            python3 "$REPORT" --since "$since" > "$TMP/out" 2>&1
    fi
    return $?
}

# assert_line <name> <regex>
assert_line() {
    if grep -Eq "$2" "$TMP/out"; then
        pass "$1"
    else
        fail "$1 (no line matched: $2)"
    fi
}

# --- case: full window -----------------------------------------------------
rc=0
run_report 2026-10-01 2026-10-04 || rc=$?
if [ "$rc" != 0 ]; then
    fail "full window: report exit 0 (got $rc)"
else
    pass "full window: report exit 0"
fi
assert_line "runs total (4, outside-window rows excluded)" '^DeepSeek runs: 4 total, 2 finished$'
assert_line "stopped by loop: 1" '^  stopped by loop: 1$'
assert_line "stopped by context: 1" '^  stopped by context: 1$'
assert_line "stopped by idle: 0" '^  stopped by idle: 0$'
assert_line "cost sum 0.850 (null counted 0)" '^DeepSeek total cost: \$0\.850 USD'
assert_line "single requests excluded from runs (2)" '^DeepSeek single requests: 2$'
assert_line "dispatches by decision" '^dispatches: allow 6, block 1, bypass 1$'
assert_line "allowed sonnet fallback labelled" 'sonnet fallback 1'
assert_line "allowed+bypass opus unlabelled (2)" 'opus none 2'
assert_line "allowed inherit unlabelled" 'inherit none 1'
if grep -Eq 'sonnet none 1' "$TMP/out"; then
    fail "blocked sonnet excluded from the model/label breakdown"
else
    pass "blocked sonnet excluded from the model/label breakdown"
fi
if grep -Eq 'sonnet research 1' "$TMP/out"; then
    pass "research shown in the breakdown"
else
    fail "research shown in the breakdown"
fi
assert_line "share: DeepSeek 4 runs, share 4 (blocked/research/haiku out), 50%" \
    '^implementation share: DeepSeek 4 runs, sonnet/opus/inherit 4 \(fallback \+ bypass \+ unlabelled-allowed\), DeepSeek 50%$'

# --- case: window excludes later day --------------------------------------
rc=0
run_report 2026-10-01 2026-10-03 || rc=$?
if [ "$rc" != 0 ]; then
    fail "until window: report exit 0 (got $rc)"
else
    pass "until window: report exit 0"
fi
assert_line "until window excludes 10-03 (runs 3)" '^DeepSeek runs: 3 total, 1 finished$'
assert_line "until window excludes 10-04 but not 10-01 dispatches (share 4, 43%)" \
    '^implementation share: DeepSeek 3 runs, sonnet/opus/inherit 4 \(fallback \+ bypass \+ unlabelled-allowed\), DeepSeek 43%$'

# --- case: --until default (up to now) counts everything from 10-01 on ----
# The fixtures only reach 10-04, and "now" is later, so all post-since rows
# count; the 09-30 rows stay out.
rc=0
run_report 2026-10-01 || rc=$?
if [ "$rc" != 0 ]; then
    fail "default until: report exit 0 (got $rc)"
else
    pass "default until: report exit 0"
fi
assert_line "default until counts the 10-04 rows (runs 4)" \
    '^DeepSeek runs: 4 total, 2 finished$'
assert_line "default until counts the 10-03 rows but not 10-04 (share 4, 50%)" \
    '^implementation share: DeepSeek 4 runs, sonnet/opus/inherit 4 \(fallback \+ bypass \+ unlabelled-allowed\), DeepSeek 50%$'

# --- case: both files missing -> exit 0, n/a ------------------------------
MISS="$TMP/nope"
: > "$TMP/out"
rc=0
INCURSION_DEEPSEEK_LEDGER="$MISS/ledger.jsonl" \
    INCURSION_DISPATCH_LOG="$MISS/dispatch-log.jsonl" \
    python3 "$REPORT" --since 2026-10-01 > "$TMP/out" 2>&1 || rc=$?
if [ "$rc" = 0 ]; then
    pass "both files missing: exit 0"
else
    fail "both files missing: exit 0 (got $rc)"
fi
assert_line "both files missing: prints n/a" \
    '^implementation share: DeepSeek 0 runs, sonnet/opus/inherit 0 \(fallback \+ bypass \+ unlabelled-allowed\), DeepSeek n/a$'
assert_line "both files missing: names the ledger" 'ledger file missing'
assert_line "both files missing: names the dispatch log" 'dispatch log missing'

# --- case: non-JSON lines are skipped and noted ---------------------------
printf 'this is not json\n' >> "$LEDGER"
rc=0
run_report 2026-10-01 2026-10-04 || rc=$?
if [ "$rc" = 0 ]; then
    pass "non-JSON line: report exit 0"
else
    fail "non-JSON line: report exit 0 (got $rc)"
fi
assert_line "non-JSON line: skipped and counted in a note" 'ledger skipped 1 non-JSON line'
assert_line "non-JSON line: does not change the runs total" '^DeepSeek runs: 4 total, 2 finished$'

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: check_dispatch_report.sh, all cases"
    exit 0
else
    echo "FAIL: check_dispatch_report.sh, at least one case failed above"
    exit 1
fi
