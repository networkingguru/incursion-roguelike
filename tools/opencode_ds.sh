#!/bin/bash
# tools/opencode_ds.sh -- run the opencode agent harness against one worktree,
# driving DeepSeek-V4.1-Flash on DeepInfra, sandboxed and billed to the
# incursion DeepSeek ledger (bead inc-h1bq).
#
#   tools/opencode_ds.sh <worktree-dir> <brief-file>
#
# Exit 0 success; 1 refused (budget or poisoned ledger); 2 could not run or
# opencode failed.
#
# The wrapper reuses tools/deepseek.py's check_budget, resolve_ledger_path,
# resolve_budget and resolve_key -- it imports the module rather than copying
# the logic, so the ledger row format and the poison rule stay in one place.
#
# ponytail: no wall-clock timeout. macOS ships no `timeout`, and sandbox-exec
# has no built-in one either, so a wedged opencode run would hang this wrapper.
# Upgrade path: wrap the sandbox-exec call in a `perl -e 'alarm(N); exec @ARGV'`
# guard (or add coreutils' `gtimeout` to the requirements) once a bounded run
# matters more than it does today.

set -uo pipefail

usage() {
    echo "usage: tools/opencode_ds.sh <worktree-dir> <brief-file>" >&2
}

if [ "$#" -ne 2 ]; then
    usage
    exit 2
fi

ARG_WORKTREE="$1"
BRIEF_FILE="$2"

# --- paths ----------------------------------------------------------------
# REPO is the repository this script lives in, never the worktree.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEEPSEEK_MODULE="$REPO/tools/deepseek.py"
SANDBOX_PROFILE="$REPO/tools/opencode/sandbox.sb"
OPENCODE_CONFIG="$REPO/tools/opencode/opencode.json"

# --- 1. validate ----------------------------------------------------------
if [ ! -d "$ARG_WORKTREE" ]; then
    echo "refused: worktree directory does not exist: $ARG_WORKTREE" >&2
    exit 2
fi
WORKTREE="$(cd "$ARG_WORKTREE" && pwd -P)" || {
    echo "refused: could not resolve worktree directory: $ARG_WORKTREE" >&2
    exit 2
}
case "$WORKTREE" in
    /*) ;;
    *) echo "refused: worktree did not resolve to an absolute path: $WORKTREE" >&2; exit 2 ;;
esac

if [ ! -f "$BRIEF_FILE" ]; then
    echo "refused: brief file does not exist: $BRIEF_FILE" >&2
    exit 2
fi
if [ ! -s "$BRIEF_FILE" ]; then
    echo "refused: brief file is empty: $BRIEF_FILE" >&2
    exit 2
fi

# The one-worktree-per-bead rule (AGENTS.md): never run in the shared checkout.
SHARED="$HOME/Scripts/Incursion"
if [ -d "$SHARED" ]; then
    SHARED_RESOLVED="$(cd "$SHARED" && pwd -P)"
    if [ "$WORKTREE" = "$SHARED_RESOLVED" ]; then
        echo "refused: $WORKTREE is the shared checkout ($SHARED_RESOLVED)." >&2
        echo "One bead, one worktree: start with tools/worktree.sh <bead-id> and" >&2
        echo "work only in that worktree (AGENTS.md)." >&2
        exit 2
    fi
fi

for f in "$DEEPSEEK_MODULE" "$SANDBOX_PROFILE" "$OPENCODE_CONFIG"; do
    if [ ! -f "$f" ]; then
        echo "could not run: missing required file: $f" >&2
        exit 2
    fi
done

# --- 2. key ---------------------------------------------------------------
# resolve_key() exits 2 and prints its own fix command on failure. The key
# never reaches stdout, stderr, the ledger, or any file this script writes;
# it is passed to opencode only as DEEPINFRA_API_KEY in its environment.
KEY="$(python3 - "$DEEPSEEK_MODULE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("deepseek", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
sys.stdout.write(mod.resolve_key())
PY
)"
RC=$?
if [ "$RC" -ne 0 ]; then
    exit "$RC"
fi
if [ -z "$KEY" ]; then
    echo "could not run: resolve_key() returned an empty key" >&2
    exit 2
fi

# --- 3. budget ------------------------------------------------------------
# Run check_budget() in its own interpreter: it exits 1 on refusal/poison and
# 2 on a malformed ledger, and those codes must pass straight through. The
# ledger path and budget are resolved by the module itself.
python3 - "$DEEPSEEK_MODULE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("deepseek", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.check_budget(mod.resolve_ledger_path(), mod.resolve_budget())
PY
RC=$?
if [ "$RC" -ne 0 ]; then
    exit "$RC"
fi

# --- 4. run dir -----------------------------------------------------------
# logs/ is gitignored. XDG_* point inside the run dir; only the provider
# package cache is shared, so it downloads once across runs.
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUNDIR="$WORKTREE/logs/opencode/${STAMP}-$$"
mkdir -p "$RUNDIR" || { echo "could not run: cannot make run dir $RUNDIR" >&2; exit 2; }
CACHEDIR="$HOME/Library/Caches/incursion-opencode"
mkdir -p "$CACHEDIR" || { echo "could not run: cannot make cache dir $CACHEDIR" >&2; exit 2; }

EVENTS="$RUNDIR/events.jsonl"
STDERR="$RUNDIR/stderr.log"

# --- 5. launch ------------------------------------------------------------
BRIEF_TEXT="$(cat "$BRIEF_FILE")"
OPENCODE_BIN="${INCURSION_OPENCODE_BIN:-opencode}"

env \
    DEEPINFRA_API_KEY="$KEY" \
    OPENCODE_CONFIG="$OPENCODE_CONFIG" \
    OPENCODE_DISABLE_CLAUDE_CODE=1 \
    OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1 \
    OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
    OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
    OPENCODE_DISABLE_PROJECT_CONFIG=1 \
    OPENCODE_DISABLE_AUTOUPDATE=1 \
    OPENCODE_DISABLE_SHARE=1 \
    XDG_DATA_HOME="$RUNDIR/data" \
    XDG_STATE_HOME="$RUNDIR/state" \
    XDG_CONFIG_HOME="$RUNDIR/config" \
    XDG_CACHE_HOME="$CACHEDIR" \
    sandbox-exec -f "$SANDBOX_PROFILE" -D WORKDIR="$WORKTREE" -D CACHEDIR="$CACHEDIR" \
    "$OPENCODE_BIN" run --pure --format json --dir "$WORKTREE" "$BRIEF_TEXT" \
    > "$EVENTS" 2> "$STDERR"
OPENCODE_RC=$?

# --- 6. bill --------------------------------------------------------------
# Parse events.jsonl: sum part.cost and the token fields over every
# step_finish event, then append exactly one ledger row. A run with no
# step_finish event and no tokens billed nothing, so it writes no row. Any
# step_finish carrying tokens with a missing/non-numeric cost, or a total
# cost of 0 with tokens > 0, is a poison: the row goes in with cost null.
BILL_OUT="$(python3 - "$DEEPSEEK_MODULE" "$EVENTS" "$RUNDIR" "$BRIEF_FILE" "$OPENCODE_RC" <<'PY'
import importlib.util, json, sys, datetime
from pathlib import Path

module_path, events_path, rundir, brief_file, rc = sys.argv[1:6]

spec = importlib.util.spec_from_file_location("deepseek", module_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

raw = Path(events_path).read_text() if Path(events_path).exists() else ""
steps = 0
cost_total = 0.0
tokens_total = 0
input_total = 0
output_total = 0
reasoning_total = 0
cache_read_total = 0
cache_write_total = 0
have_tokens = False
cost_unknown = False

for line in raw.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        continue
    if ev.get("type") != "step_finish":
        continue
    part = ev.get("part") or {}
    steps += 1
    tokens = part.get("tokens") or {}
    step_tokens = 0
    if isinstance(tokens, dict):
        for key in ("input", "output", "reasoning", "total"):
            v = tokens.get(key)
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                step_tokens += v
        cache = tokens.get("cache") or {}
        if isinstance(cache, dict):
            for key in ("read", "write"):
                v = cache.get(key)
                if isinstance(v, (int, float)) and not isinstance(v, bool):
                    step_tokens += v
        input_total += tokens.get("input") or 0
        output_total += tokens.get("output") or 0
        reasoning_total += tokens.get("reasoning") or 0
        cache = tokens.get("cache") or {}
        if isinstance(cache, dict):
            cache_read_total += cache.get("read") or 0
            cache_write_total += cache.get("write") or 0
    if step_tokens > 0:
        have_tokens = True
    tokens_total += step_tokens
    cost = part.get("cost")
    if isinstance(cost, (int, float)) and not isinstance(cost, bool):
        cost_total += cost
    else:
        cost_unknown = True

# Nothing billed: no step_finish and no tokens.
if steps == 0 and not have_tokens:
    print("BILL nothing")
    print("STEPS 0")
    print("COST 0")
    print("POISON 0")
    sys.exit(0)

# Poison: a priced field is missing/not a number, or tokens > 0 priced at 0.
poison = cost_unknown or (have_tokens and cost_total == 0)
# Round away binary-float noise (0.1 + 0.05 -> 0.15000000000000002).
cost_total = round(cost_total, 6)

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
row = {
    "ts": ts,
    "model": mod.MODEL,
    "prompt": str(brief_file),
    "out": str(rundir),
    "prompt_tokens": input_total,
    "completion_tokens": output_total,
    "cached_tokens": cache_read_total,
    "cost": None if poison else cost_total,
    "id": None,
    "harness": "opencode",
    "cost_source": "opencode-estimate",
    "steps": steps,
}
mod.append_ledger_row(mod.resolve_ledger_path(), row)

print("BILL row")
print("STEPS %d" % steps)
print("COST %s" % ("" if poison else repr(cost_total)))
print("POISON %d" % (1 if poison else 0))
PY
)"
BILL_RC=$?
if [ "$BILL_RC" -ne 0 ]; then
    echo "could not run: billing parse failed (rc=$BILL_RC); events are in $RUNDIR" >&2
    exit 2
fi

STEPS="$(printf '%s\n' "$BILL_OUT" | sed -n 's/^STEPS //p')"
COST="$(printf '%s\n' "$BILL_OUT" | sed -n 's/^COST //p')"
POISON="$(printf '%s\n' "$BILL_OUT" | sed -n 's/^POISON //p')"

# --- 7. report ------------------------------------------------------------
# Final assistant text: the last type == "text" event's part.text.
FINAL_TEXT="$(python3 - "$EVENTS" <<'PY'
import json, sys
from pathlib import Path
last = ""
raw = Path(sys.argv[1]).read_text() if Path(sys.argv[1]).exists() else ""
for line in raw.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        continue
    if ev.get("type") == "text":
        part = ev.get("part") or {}
        if isinstance(part.get("text"), str):
            last = part["text"]
sys.stdout.write(last)
PY
)"
if [ -n "$FINAL_TEXT" ]; then
    printf '%s\n' "$FINAL_TEXT"
fi

if [ "$POISON" -eq 1 ]; then
    echo "rundir=$RUNDIR steps=$STEPS cost=null exit=$OPENCODE_RC"
    echo "opencode run quoted no usable cost; ledger row written with cost=null." >&2
    echo "The ledger is now POISONED until a human resolves that row." >&2
    exit 2
fi

echo "rundir=$RUNDIR steps=$STEPS cost=$COST exit=$OPENCODE_RC"

if [ "$OPENCODE_RC" -ne 0 ]; then
    echo "opencode exited $OPENCODE_RC; see $STDERR" >&2
    exit 2
fi

exit 0
