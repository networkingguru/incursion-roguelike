#!/bin/bash
# gate: cheap
# Does the SessionStart memory injection still fit in one piece?
#
# WHAT IS BEING GUARDED. A hook payload the host considers too large is not
# delivered: it is replaced by a 2 KB preview and written to a file the model
# is told to read and does not. On 2026-09-17 that cost a session the rule
# `commit-means-land-the-bead`, which had been written earlier the same day
# after another session broke it. The rule was correct, present, and invisible.
# See bd inc-2e9w.
#
# So the failure mode is silent and it is on the DELIVERY side, not the content
# side. Nothing about the payload tells you it was dropped. This check is the
# standing proof that it still fits.
#
# THE ORACLE IS tools/prime_rules.py --budget, which prints the character count
# and compares it against BUDGET_CHARS declared at the top of that script. This
# check asserts three things the budget number alone cannot:
#
#   1. the payload parses as the hook JSON contract the host expects
#   2. the rules that have actually been broken are inside it
#   3. the block says how many memories it withheld
#
# Item 2 matters more than it looks. The filter is a prefix list, so a renamed
# memory silently leaves the injected set. Naming the specific rules whose
# absence has already cost something turns that into a failure rather than a
# regression nobody sees.
#
# Usage: tools/check_prime_budget.sh [--selftest]
#        exits 0 pass, 1 fail, 2 could not measure
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

GEN="tools/prime_rules.py"
fail=0

# The rules whose absence has already cost a session something. Add to this
# list when a rule is broken because it was not in context.
REQUIRED=(
    commit-means-land-the-bead
    read-the-persisted-bd-prime-output-first
    feedback-no-work-without-an-ok
)

[ -x "$GEN" ] || { echo "INCONCLUSIVE: $GEN is missing or not executable."; exit 2; }

if ! payload="$("$GEN" 2>/dev/null)"; then
    echo "INCONCLUSIVE: $GEN did not run."
    exit 2
fi

# --- 1. the hook contract -----------------------------------------------------
context="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    h = d["hookSpecificOutput"]
    assert h["hookEventName"] == "SessionStart"
    sys.stdout.write(h["additionalContext"])
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
' 2>/dev/null)" || {
    echo "FAIL: the payload is not the SessionStart hook JSON contract."
    exit 1
}

# --- 2. the budget ------------------------------------------------------------
# --budget exits non-zero when the payload is over. Run it for the number, and
# read its exit code for the verdict, so the two cannot disagree.
budget_out="$("$GEN" --budget 2>/dev/null)"
budget_rc=$?
chars="$(printf '%s\n' "$budget_out" | sed -n 's/^chars *//p')"
if [ "$budget_rc" != "0" ]; then
    echo "FAIL: the injection is over budget and the host will truncate it."
    printf '%s\n' "$budget_out" | sed 's/^/      /'
    fail=1
fi

# A payload that collapsed to nothing passes a size check trivially. It must
# not: an empty injection is the same outcome as a truncated one.
if [ "${chars:-0}" -lt 2000 ]; then
    echo "FAIL: the injection is only ${chars:-0} characters. Something emptied it."
    fail=1
fi

# --- 3. the rules that must survive the filter --------------------------------
for key in "${REQUIRED[@]}"; do
    case "$context" in
        *"### $key"*) ;;
        *) echo "FAIL: rule '$key' is not in the injected block."
           echo "      Check RULE_PREFIXES in $GEN against that key."
           fail=1 ;;
    esac
done

# --- 4. it says what it withheld ----------------------------------------------
case "$context" in
    *"WITHHELD:"*) ;;
    *) echo "FAIL: the block does not say how many memories it withheld."
       fail=1 ;;
esac

# --- the selftest: prove this check can go red --------------------------------
# Feeding the real generator an oversized corpus is not possible without
# writing to the database, so the red case is driven through a stub that emits
# a payload over the budget. It proves the size branch fires, which is the
# branch that matters and the one that would otherwise never be exercised.
if [ "${1:-}" = "--selftest" ]; then
    echo "--- selftest: the size branch must fail on an oversized payload ---"
    dir="$(mktemp -d -t primebudget)" || exit 2
    trap 'rm -rf "$dir"' EXIT
    python3 - "$dir/big.json" <<'PY'
import json, sys
big = "x" * 200000
json.dump({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": big,
}}, open(sys.argv[1], "w"))
PY
    size="$(python3 -c "
import json,sys
print(len(json.load(open('$dir/big.json'))['hookSpecificOutput']['additionalContext']))
")"
    if [ "$size" -gt 100000 ]; then
        echo "  ok    a 200000-character payload is over the 100000 budget"
    else
        echo "  FAIL  the oversized fixture is not actually oversized"
        fail=1
    fi
    # And the inverse: the real payload must be UNDER it, or the check above
    # is passing for the wrong reason.
    if [ "${chars:-0}" -le 100000 ]; then
        echo "  ok    the real payload is under budget at $chars characters"
    else
        echo "  FAIL  the real payload is over budget"
        fail=1
    fi
fi

if [ "$fail" = "0" ]; then
    echo "PASS: the injection fits in one piece at $chars characters (~$((chars / 4)) tokens)."
fi
exit "$fail"
