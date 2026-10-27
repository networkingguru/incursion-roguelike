#!/bin/bash
# gate: cheap
# Does tools/claude_budget.py decide the coding route from Claude Code's
# seven-day rate-limit window exactly as specified? Defends bead inc-cfnm: the
# boundary is strict (used < threshold), the day is derived from `resets_at`
# and clamped to 1..7, day 7 has a flat 100% threshold, a passed `resets_at`
# resets the window to day 1 with used 0, a missing/non-JSON/no-seven_day file
# or a stale mtime (more than 3600s) is UNKNOWN (exit 2), and a verdict line is
# printed as `claude-budget: day D, weekly used U%, threshold T% -> WORD`.
#
# Fully offline, against a temp usage file (env INCURSION_CLAUDE_USAGE), with
# `now` pinned by INCURSION_CLAUDE_BUDGET_NOW and the file's mtime set with
# os.utime. Every case asserts the exit code AND the stdout verdict word.
#
#   tools/check_claude_budget.sh               run the cases
#   tools/check_claude_budget.sh --prove-red   mutate the day-7 threshold from
#                                              100 to 65, confirm the
#                                              "day 7, used 99" case goes red,
#                                              restore, and verify the restore
#                                              with cmp
#
# Exit: 0 pass, 1 fail, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/tools/claude_budget.py"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/claude-budget-check.XXXXXX")" || exit 2
USAGE="$TMP/statusline.json"
BACKUP=""

cleanup() {
    if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$GATE"
        if cmp -s "$BACKUP" "$GATE"; then
            echo "restored tools/claude_budget.py byte-identical to its original"
        else
            echo "COULD NOT CONFIRM tools/claude_budget.py WAS RESTORED -- check it by hand" >&2
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
    PROVE_FAIL=0
    BACKUP="$TMP/claude_budget.py.orig"
    cp "$GATE" "$BACKUP"

    NEEDLE=$'day = max(1, min(7, day))\n\n    threshold = THRESHOLDS[day - 1]'
    if ! grep -qF "$NEEDLE" "$GATE"; then
        echo "could not find the day-7 threshold to mutate: $NEEDLE" >&2
        exit 2
    fi
    python3 - "$GATE" "$NEEDLE" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path).read()
open(path, "w").write(src.replace(
    needle, 'day = max(1, min(7, day))\n\n    threshold = 65 if day == 7 else THRESHOLDS[day - 1]  # MUTATED by --prove-red', 1))
PY
    echo "mutated tools/claude_budget.py: day-7 threshold 100 -> 65"

    MUTATED_OUTPUT="$("$ROOT/tools/check_claude_budget.sh")"
    MUTATED_RC=$?
    echo "--- output of the mutated run ---"
    echo "$MUTATED_OUTPUT"
    echo "--- end output of the mutated run ---"

    if [ "$MUTATED_RC" -ne 0 ] && grep -q 'FAIL.*day 7, used 99' <<< "$MUTATED_OUTPUT"; then
        echo "PASS (as intended): the 'day 7, used 99' case went red under the mutation"
    else
        echo "FAIL: the 'day 7, used 99' case did not go red with the day-7 threshold lowered (rc=$MUTATED_RC)"
        PROVE_FAIL=1
    fi

    cp "$BACKUP" "$GATE"
    cmp -s "$BACKUP" "$GATE" || { echo "restore of claude_budget.py failed" >&2; exit 2; }

    if [ "$PROVE_FAIL" -eq 0 ]; then
        echo "PASS: --prove-red, the mutation turned its intended case red"
        exit 0
    fi
    exit 1
fi

# --- helpers --------------------------------------------------------------
# Write a usage file. Usage: write_usage <used_percentage> <resets_at> [k=v...]
# Extra key=value pairs become top-level rate_limits keys (for the fixtures
# that must omit seven_day or corrupt it).
write_usage() {
    python3 - "$USAGE" "$@" <<'PY'
import json, sys
path, used, resets = sys.argv[1], sys.argv[2], sys.argv[3]
seven = {}
if used != "MISSING_USED":
    seven["used_percentage"] = float(used) if "." in used else int(used)
if resets != "MISSING_RESETS":
    seven["resets_at"] = int(resets)
data = {"rate_limits": {"seven_day": seven}}
open(path, "w").write(json.dumps(data))
PY
}

# Replace the top-level rate_limits object wholesale. Usage:
#   write_raw <json-text-of-rate-limits-or-NONE>
write_raw() {
    python3 - "$USAGE" "$1" <<'PY'
import json, sys
path, rl = sys.argv[1], sys.argv[2]
data = {} if rl == "NONE" else {"rate_limits": json.loads(rl)}
open(path, "w").write(json.dumps(data))
PY
}

# Set the usage file's mtime to $1 seconds before $2 (both Unix seconds).
set_mtime() {
    python3 - "$USAGE" "$1" "$2" <<'PY'
import os, sys
path, age, now = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
os.utime(path, (now - age, now - age))
PY
}

# Run the gate with the temp usage path and pinned now. Usage:
#   run_verdict <now>
run_verdict() {
    INCURSION_CLAUDE_USAGE="$USAGE" INCURSION_CLAUDE_BUDGET_NOW="$1" \
        python3 "$GATE" > "$TMP/last.out" 2> "$TMP/last.stderr"
    return $?
}

# expect <name> <want_rc> <want_word> <got_rc>
# want_word is the verdict word ("sonnet-first"/"normal") or "" for UNKNOWN.
expect() {
    local name="$1" want_rc="$2" want_word="$3" got_rc="$4"
    local got_word
    if [ -z "$want_word" ]; then
        if [ "$got_rc" = "$want_rc" ] && [ ! -s "$TMP/last.out" ]; then
            pass "$name"
        else
            fail "$name (rc=$got_rc, stdout=$(cat "$TMP/last.out"))"
        fi
        return
    fi
    got_word="$(sed -n 's/.* -> \([a-z-]*\)$/\1/p' "$TMP/last.out")"
    if [ "$got_rc" = "$want_rc" ] && [ "$got_word" = "$want_word" ]; then
        pass "$name"
    else
        fail "$name (rc=$got_rc word=$got_word; wanted rc=$want_rc word=$want_word)"
    fi
}

# --- fixtures -------------------------------------------------------------
# `now` is fixed; resets_at is chosen so the day lands well inside the day.
NOW=1792410600
# Day 1: start = resets_at - 604800, so now - start in [0, 86400).
R_DAY1=$((NOW + 604800 - 43200))
# Day 3: now - start in [172800, 259200).
R_DAY3=$((NOW + 604800 - 216000))
# Day 6: now - start in [432000, 518400).
R_DAY6=$((NOW + 604800 - 475200))
# Day 7: now - start in [518400, 604800).
R_DAY7=$((NOW + 604800 - 561600))
# Already reset: resets_at at or before now.
R_PAST=$((NOW - 3600))

# --- case: day 1 boundary is strict --------------------------------------
write_usage 9 "$R_DAY1"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "day 1, used 9: sonnet-first" 0 sonnet-first "$rc"

write_usage 10 "$R_DAY1"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "day 1, used 10: normal" 1 normal "$rc"

# --- case: day 3 boundary ------------------------------------------------
write_usage 34 "$R_DAY3"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "day 3, used 34: sonnet-first" 0 sonnet-first "$rc"

write_usage 35 "$R_DAY3"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "day 3, used 35: normal" 1 normal "$rc"

# --- case: day 6 and day 7 thresholds ------------------------------------
write_usage 64 "$R_DAY6"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "day 6, used 64: sonnet-first" 0 sonnet-first "$rc"

write_usage 99 "$R_DAY7"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "day 7, used 99: sonnet-first" 0 sonnet-first "$rc"

write_usage 100 "$R_DAY7"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "day 7, used 100: normal" 1 normal "$rc"

# --- case: window already reset ------------------------------------------
write_usage 99 "$R_PAST"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "now >= resets_at, used 99: sonnet-first (window reset)" 0 sonnet-first "$rc"

# --- case: UNKNOWN fixtures ----------------------------------------------
rm -f "$USAGE"
rc=0; run_verdict "$NOW" || rc=$?
expect "missing file: exit 2" 2 "" "$rc"

printf 'not json' > "$USAGE"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "non-JSON file: exit 2" 2 "" "$rc"

write_raw '{"five_hour": {"used_percentage": 3}}'; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "no seven_day: exit 2" 2 "" "$rc"

# --- case: nonsensical numbers -------------------------------------------
write_usage -1 "$R_DAY1"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "used -1: exit 2" 2 "" "$rc"

write_usage 101 "$R_DAY1"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "used 101: exit 2" 2 "" "$rc"

write_usage 4 0; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "resets_at 0: exit 2" 2 "" "$rc"

# --- case: file that is not UTF-8 ----------------------------------------
printf '\xff\xfe\x00' > "$USAGE"; set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "non-UTF-8 file: exit 2" 2 "" "$rc"

# --- case: Infinity used_percentage --------------------------------------
printf '{"rate_limits":{"seven_day":{"used_percentage":-Infinity,"resets_at":%d}}}' "$R_DAY1" > "$USAGE"
set_mtime 60 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "used Infinity: exit 2" 2 "" "$rc"

# --- case: staleness boundary --------------------------------------------
write_usage 4 "$R_DAY1"; set_mtime 3601 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
expect "mtime 3601s before now: exit 2" 2 "" "$rc"

write_usage 4 "$R_DAY1"; set_mtime 3599 "$NOW"
rc=0; run_verdict "$NOW" || rc=$?
if [ "$rc" = 2 ]; then
    fail "mtime 3599s before now: exit 2 (expected not 2)"
else
    pass "mtime 3599s before now: not exit 2"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: check_claude_budget.sh, all cases"
    exit 0
else
    echo "FAIL: check_claude_budget.sh, at least one case failed above"
    exit 1
fi
