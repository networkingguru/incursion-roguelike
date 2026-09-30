#!/bin/bash
# gate: cheap
#
# Does tools/opencode_ds.sh refuse to launch once the DeepSeek ledger says the
# budget is gone or poisoned, refuse the shared checkout, bill exactly one
# ledger row for a successful harness run (cost = the sum of its step_finish
# costs, steps = the count), poison the ledger when opencode quotes tokens but
# no usable cost, keep the API key out of every file it writes, confine
# opencode to the worktree with the Seatbelt profile, stop a harness that
# never writes -- billing it as one killed=startup row at cost 0 -- and stop a
# harness stuck in a DeepSeek repetition loop via the loop_check.py canary,
# billing it as one killed=loop row at exit 3 and copying its events aside?
# Defends beads inc-h1bq, inc-gofz and inc-uxmf: the opencode rung of the
# implementer ladder must fail closed rather than silently spend money once a
# run's price is unknown, must never touch the shared checkout, must not hang
# its dispatcher when the harness stalls, and must not burn tokens on a loop.
#
# Fully offline. A fake `opencode` written into the temp dir stands in for the
# real harness via INCURSION_OPENCODE_BIN; it records its argv and environment
# and emits scripted events.jsonl (the loop case cats
# tools/fixtures/opencode-loop/loop.jsonl). No network request ever leaves this
# machine.
#
#   tools/check_opencode_ds.sh               run the thirteen assertions
#   tools/check_opencode_ds.sh --prove-red   mutate the budget guard, the
#                                            sandbox prefix, the JSON bash
#                                            rules and MIN_REPEATED_LINES,
#                                            confirm red
#
# Exit: 0 pass, 1 fail, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="$ROOT/tools/opencode_ds.sh"
CONFIG="$ROOT/tools/opencode/opencode.json"
PROFILE="$ROOT/tools/opencode/sandbox.sb"

TMP="$(mktemp -d)" || exit 2
# The genuine home, captured before any assertion overrides HOME. The sandbox
# confinement assertion writes outside every allowed subpath by targeting a
# dotfile here: the Seatbelt profile allows WORKDIR, CACHEDIR, /private/tmp and
# /private/var/folders (where $TMP itself lives), so the real home is the only
# nearby location the profile denies.
REAL_HOME="$HOME"
PROBE_OUTSIDE=""
BACKUP=""
BACKUP_PROFILE=""
BACKUP_CONFIG=""

cleanup() {
    if [ -n "${PROBE_OUTSIDE:-}" ]; then
        rm -f "$PROBE_OUTSIDE"
    fi
    if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$WRAPPER"
        if cmp -s "$BACKUP" "$WRAPPER"; then
            echo "restored tools/opencode_ds.sh byte-identical to its original"
        else
            echo "COULD NOT CONFIRM tools/opencode_ds.sh WAS RESTORED -- check it by hand" >&2
        fi
    fi
    if [ -n "$BACKUP_PROFILE" ] && [ -f "$BACKUP_PROFILE" ]; then
        cp "$BACKUP_PROFILE" "$PROFILE"
        if cmp -s "$BACKUP_PROFILE" "$PROFILE"; then
            echo "restored tools/opencode/sandbox.sb byte-identical to its original"
        else
            echo "COULD NOT CONFIRM sandbox.sb WAS RESTORED -- check it by hand" >&2
        fi
    fi
    if [ -n "$BACKUP_CONFIG" ] && [ -f "$BACKUP_CONFIG" ]; then
        cp "$BACKUP_CONFIG" "$CONFIG"
        if cmp -s "$BACKUP_CONFIG" "$CONFIG"; then
            echo "restored tools/opencode/opencode.json byte-identical to its original"
        else
            echo "COULD NOT CONFIRM opencode.json WAS RESTORED -- check it by hand" >&2
        fi
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

FAIL=0
SKIP_COUNT=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }
skip() { echo "SKIP  $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

# --- --prove-red ----------------------------------------------------------
# Handled FIRST, before the eleven assertions below ever run. Four mutations,
# each restoring the file it touches: (a) drop the budget-check call, so
# assertion 1 must go red; (b) drop the `sandbox-exec` prefix, so assertion 7
# must go red; (c) strip the read-only-git allow rules from opencode.json, so
# assertion 10 must go red; (d) drop `"git *": "deny"` from opencode.json, so
# assertion 10 must go red. Original files are restored, and each restoration
# verified byte-identical with cmp, by the EXIT trap above.
if [ "${1:-}" = "--prove-red" ]; then
    PROVE_FAIL=0
    # sandbox-exec cannot nest: under another Seatbelt sandbox, mutation (b) --
    # which removes the sandbox prefix -- cannot be proven, because the outer
    # sandbox denies the out-of-worktree write whether or not the wrapper's
    # sandbox is present. Detect that and report (b) as not run rather than
    # claiming a proof this environment did not earn.
    SANDBOX_RUNNABLE=1
    if ! sandbox-exec -p '(version 1)(allow default)' /usr/bin/true >/dev/null 2>&1; then
        SANDBOX_RUNNABLE=0
    fi

    # (a) budget guard removed.
    BACKUP="$TMP/opencode_ds.sh.orig"
    cp "$WRAPPER" "$BACKUP"
    NEEDLE='mod.check_budget(mod.resolve_ledger_path(), mod.resolve_budget())'
    if ! grep -qF "$NEEDLE" "$WRAPPER"; then
        echo "could not find the budget check to mutate: $NEEDLE" >&2
        exit 2
    fi
    python3 - "$WRAPPER" "$NEEDLE" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path).read()
open(path, "w").write(src.replace(needle, "pass  # MUTATED by --prove-red", 1))
PY
    echo "mutated tools/opencode_ds.sh: budget check disabled"
    MUT_OUT="$("$ROOT/tools/check_opencode_ds.sh" 2>&1)"
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ] && grep -q "FAIL.*budget" <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion 1 (budget) went red"
    else
        echo "FAIL: assertion 1 stayed green under a disabled budget check (rc=$MUT_RC)"
        echo "$MUT_OUT" | tail -20
        PROVE_FAIL=1
    fi
    cp "$BACKUP" "$WRAPPER"
    cmp -s "$BACKUP" "$WRAPPER" || { echo "restore of opencode_ds.sh failed" >&2; exit 2; }

    # (e) loop_check.py's MIN_REPEATED_LINES raised out of reach, so the real
    # loop fixture must no longer be called a loop and assertion 13 must go red.
    LOOP_CHECK="$ROOT/tools/opencode/loop_check.py"
    BACKUP_LOOP="$TMP/loop_check.py.orig"
    cp "$LOOP_CHECK" "$BACKUP_LOOP"
    NEEDLE='MIN_REPEATED_LINES = 15'
    if ! grep -qF "$NEEDLE" "$LOOP_CHECK"; then
        echo "could not find MIN_REPEATED_LINES to mutate" >&2
        exit 2
    fi
    python3 - "$LOOP_CHECK" "$NEEDLE" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path).read()
open(path, "w").write(src.replace(needle, "MIN_REPEATED_LINES = 10000", 1))
PY
    echo "mutated tools/opencode/loop_check.py: MIN_REPEATED_LINES = 10000"
    MUT_OUT="$("$ROOT/tools/check_opencode_ds.sh" 2>&1)"
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ] && grep -q "FAIL.*loop_check" <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion 13 (loop_check) went red"
    else
        echo "FAIL: assertion 13 stayed green with MIN_REPEATED_LINES = 10000 (rc=$MUT_RC)"
        echo "$MUT_OUT" | tail -20
        PROVE_FAIL=1
    fi
    cp "$BACKUP_LOOP" "$LOOP_CHECK"
    cmp -s "$BACKUP_LOOP" "$LOOP_CHECK" || { echo "restore of loop_check.py failed" >&2; exit 2; }

    # (c) the read-only-git allow rules removed from opencode.json. Assertion
    # 10 never launches the harness, so this proof runs in any environment --
    # it is placed before (b), whose early exit under a nested sandbox would
    # otherwise skip it.
    BACKUP_CONFIG="$TMP/opencode.json.orig"
    cp "$CONFIG" "$BACKUP_CONFIG"
    python3 - "$CONFIG" <<'PY'
import json, sys
path = sys.argv[1]
cfg = json.load(open(path))
bash = cfg["permission"]["bash"]
allowed = ("git status", "git status *", "git diff", "git diff *", "git log",
           "git log *", "git show", "git show *", "git ls-files",
           "git ls-files *", "git rev-parse *")
for key in allowed:
    bash.pop(key, None)
json.dump(cfg, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
    echo "mutated tools/opencode/opencode.json: read-only-git allow rules removed"
    MUT_OUT="$("$ROOT/tools/check_opencode_ds.sh" 2>&1)"
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ] && grep -q "FAIL.*git" <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion 10 (read-only git) went red"
    else
        echo "FAIL: assertion 10 stayed green with the allow rules removed (rc=$MUT_RC)"
        echo "$MUT_OUT" | tail -20
        PROVE_FAIL=1
    fi
    cp "$BACKUP_CONFIG" "$CONFIG"
    cmp -s "$BACKUP_CONFIG" "$CONFIG" || { echo "restore of opencode.json failed" >&2; exit 2; }

    # (d) `"git *": "deny"` removed from opencode.json. With that block gone the
    # later allow rules still decide for the read-only commands; a command no
    # allow rule matches would fall to `"*": "allow"`, so assertion 10 must go
    # red for the denied set. If the file's ordering ever makes this green,
    # report it rather than weakening the test.
    python3 - "$CONFIG" <<'PY'
import json, sys
path = sys.argv[1]
cfg = json.load(open(path))
bash = cfg["permission"]["bash"]
bash.pop("git *", None)
json.dump(cfg, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
    echo "mutated tools/opencode/opencode.json: \"git *\": \"deny\" removed"
    MUT_OUT="$("$ROOT/tools/check_opencode_ds.sh" 2>&1)"
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ] && grep -q "FAIL.*git" <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion 10 (read-only git) went red"
    else
        echo "FAIL: assertion 10 stayed green with \"git *\": \"deny\" removed (rc=$MUT_RC)"
        echo "$MUT_OUT" | tail -20
        PROVE_FAIL=1
    fi
    cp "$BACKUP_CONFIG" "$CONFIG"
    cmp -s "$BACKUP_CONFIG" "$CONFIG" || { echo "restore of opencode.json failed" >&2; exit 2; }

    # (b) sandbox-exec prefix removed.
    if [ "$SANDBOX_RUNNABLE" -eq 0 ]; then
        echo "SKIP (b): sandbox-exec cannot run inside this sandbox, so removing"
        echo "          the sandbox prefix cannot be distinguished from the outer"
        echo "          sandbox's own denial. Run --prove-red outside any sandbox."
        cp "$BACKUP" "$WRAPPER" 2>/dev/null
        if [ "$PROVE_FAIL" -eq 0 ]; then
            echo "INCONCLUSIVE: mutation (a) proven; mutation (b) needs an unsandboxed run"
            exit 2
        fi
        exit 1
    fi
    BACKUP="$TMP/opencode_ds.sh.orig2"
    BACKUP_PROFILE="$TMP/sandbox.sb.orig"
    cp "$WRAPPER" "$BACKUP"
    cp "$PROFILE" "$BACKUP_PROFILE"
    NEEDLE='sandbox-exec -f "$SANDBOX_PROFILE" -D WORKDIR="$WORKTREE" -D CACHEDIR="$CACHEDIR" -D HOME="$HOME" \'
    if ! grep -qF "$NEEDLE" "$WRAPPER"; then
        echo "could not find the sandbox-exec prefix to mutate" >&2
        exit 2
    fi
    python3 - "$WRAPPER" "$NEEDLE" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path).read()
replacement = 'env -u SANDBOX_EXEC_MUTATED \\'
open(path, "w").write(src.replace(needle, replacement, 1))
PY
    # With no sandbox, the out-of-worktree write succeeds and assertion 7 must
    # fail, so a green assertion 7 is the tell that the guard was removed.
    echo "mutated tools/opencode_ds.sh: sandbox-exec prefix removed"
    MUT_OUT="$("$ROOT/tools/check_opencode_ds.sh" 2>&1)"
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ] && grep -q "FAIL.*sandbox" <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion 7 (sandbox) went red"
    else
        echo "FAIL: assertion 7 stayed green without the sandbox (rc=$MUT_RC)"
        echo "$MUT_OUT" | tail -20
        PROVE_FAIL=1
    fi
    cp "$BACKUP" "$WRAPPER"
    cmp -s "$BACKUP" "$WRAPPER" || { echo "restore of opencode_ds.sh failed" >&2; exit 2; }

    if [ "$PROVE_FAIL" -eq 0 ]; then
        echo "PASS: --prove-red, all mutations turned the intended assertion red"
        exit 0
    fi
    exit 1
fi

# --- offline fixture ------------------------------------------------------
# A fake `opencode` that records its argv and environment, emits scripted
# events.jsonl, and (when told) tries a write outside the worktree. It is
# invoked by opencode_ds.sh through INCURSION_OPENCODE_BIN.
FAKE="$TMP/opencode"
cat > "$FAKE" <<'FAKE_EOF'
#!/bin/bash
REC="$INCURSION_FAKE_REC"
{
    for a in "$@"; do printf 'ARG %s\n' "$a"; done
    printf 'ENV OPENCODE_DISABLE_CLAUDE_CODE=%s\n' "${OPENCODE_DISABLE_CLAUDE_CODE:-}"
    printf 'ENV OPENCODE_CONFIG=%s\n' "${OPENCODE_CONFIG:-}"
    printf 'ENV DEEPINFRA_API_KEY=%s\n' "${DEEPINFRA_API_KEY:-}"
} >> "$REC"

MODE="${INCURSION_FAKE_MODE:-success}"
case "$MODE" in
    success)
        cat <<'JSON'
{"type":"text","timestamp":1,"sessionID":"s","part":{"type":"text","text":"fake assistant reply"}}
{"type":"step_finish","timestamp":2,"sessionID":"s","part":{"type":"step-finish","reason":"stop","cost":0.10,"tokens":{"input":100,"output":20,"reasoning":0,"total":120,"cache":{"read":10,"write":0}}}}
{"type":"step_finish","timestamp":3,"sessionID":"s","part":{"type":"step-finish","reason":"stop","cost":0.05,"tokens":{"input":50,"output":10,"reasoning":0,"total":60,"cache":{"read":5,"write":0}}}}
JSON
        ;;
    no-cost)
        cat <<'JSON'
{"type":"text","timestamp":1,"sessionID":"s","part":{"type":"text","text":"fake assistant reply"}}
{"type":"step_finish","timestamp":2,"sessionID":"s","part":{"type":"step-finish","reason":"stop","tokens":{"input":100,"output":20,"reasoning":0,"total":120,"cache":{"read":0,"write":0}}}}
JSON
        ;;
    sandbox)
        cat <<'JSON'
{"type":"text","timestamp":1,"sessionID":"s","part":{"type":"text","text":"fake assistant reply"}}
{"type":"step_finish","timestamp":2,"sessionID":"s","part":{"type":"step-finish","reason":"stop","cost":0.02,"tokens":{"input":10,"output":2,"reasoning":0,"total":12,"cache":{"read":0,"write":0}}}}
JSON
        if [ -n "${INCURSION_FAKE_WORKDIR:-}" ]; then
            ( : > "$INCURSION_FAKE_WORKDIR/inside-workdir.txt" ) 2>>"$REC" \
                && echo "WRITE INSIDE WORKDIR ok" >> "$REC" \
                || echo "WRITE INSIDE WORKDIR failed" >> "$REC"
        fi
        if [ -n "${INCURSION_FAKE_OUTSIDE:-}" ]; then
            ( : > "$INCURSION_FAKE_OUTSIDE" ) 2>>"$REC" \
                && echo "WRITE OUTSIDE ok" >> "$REC" \
                || echo "WRITE OUTSIDE failed" >> "$REC"
        fi
        ;;
    empty)
        : # no events at all: nothing billed
        ;;
    loop)
        # Emit a real loop step, then keep the harness alive so the watchdog's
        # canary (loop_check.py) fires rather than the idle limit.
        cat "${INCURSION_FAKE_EVENTS:-/dev/null}"
        sleep 1000
        ;;
    never)
        sleep 1000  # writes nothing: the watchdog's startup limit must fire
        ;;
esac
exit "${INCURSION_FAKE_RC:-0}"
FAKE_EOF
chmod +x "$FAKE"

# --- sandbox availability probe ------------------------------------------
# sandbox-exec cannot nest: inside another Seatbelt sandbox (a Claude session
# running this check), `sandbox-exec` itself refuses to apply and exits 71.
# The assertions that need to LAUNCH the harness (4, 5, 6, 7, 11) cannot run
# in that environment. Detect it once and report those as SKIP; outside any
# sandbox they all run. Assertions 1, 2, 3, 8, 9 and 10 never launch the
# harness.
SANDBOX_OK=1
PROBE_HOME="$TMP/homeprobe"; mkdir -p "$PROBE_HOME"
PROBE_WORK="$TMP/wtprobe"; mkdir -p "$PROBE_WORK"
PROBE_BRIEF="$TMP/briefprobe.txt"; echo "probe" > "$PROBE_BRIEF"
PROBE_LEDGER="$TMP/ledgerprobe.jsonl"; : > "$PROBE_LEDGER"
PROBE_RC="$(HOME="$PROBE_HOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.probe" \
    INCURSION_FAKE_MODE=empty INCURSION_DEEPSEEK_KEY=canary-x \
    INCURSION_DEEPSEEK_LEDGER="$PROBE_LEDGER" \
    "$WRAPPER" "$PROBE_WORK" "$PROBE_BRIEF" > "$TMP/out.probe" 2> "$TMP/err.probe"; echo $?)"
# sandbox-exec writes its refusal to the run dir's stderr.log, not the
# wrapper's own stderr.
if grep -rq "sandbox_apply: Operation not permitted" "$PROBE_WORK/logs/opencode" 2>/dev/null; then
    SANDBOX_OK=0
    echo "NOTE  sandbox-exec cannot nest inside this check's own sandbox;"
    echo "      assertions 4, 5, 6, 7 and 11 are reported SKIP here and must be run"
    echo "      outside any sandbox (the Claude session will do so)."
fi

# --- 1. Budget spent -> exit 1, fake never launched, no ledger row --------
WORK="$TMP/wt1"; mkdir -p "$WORK"
BRIEF="$TMP/brief1.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger1.jsonl"; printf '%s\n' '{"cost": 25.00}' > "$LEDGER"
: > "$TMP/rec.1"
RC="$(INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.1" INCURSION_FAKE_MODE=success \
    INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.1" 2> "$TMP/err.1"; echo $?)"
if [ "$RC" -eq 1 ] && [ ! -s "$TMP/rec.1" ] \
    && [ "$(wc -l < "$LEDGER" | tr -d ' ')" -eq 1 ]; then
    pass "budget refuses before it spends: exit 1, fake never launched, no new row"
else
    fail "budget refusal: rc=$RC rec=$(cat "$TMP/rec.1" 2>/dev/null) ledger=$(cat "$LEDGER") -- $(cat "$TMP/err.1")"
fi

# --- 2. Poisoned ledger -> exit 1, fake never launched --------------------
WORK="$TMP/wt2"; mkdir -p "$WORK"
BRIEF="$TMP/brief2.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger2.jsonl"; printf '%s\n' '{"cost": null}' > "$LEDGER"
: > "$TMP/rec.2"
RC="$(INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.2" INCURSION_FAKE_MODE=success \
    INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.2" 2> "$TMP/err.2"; echo $?)"
if [ "$RC" -eq 1 ] && [ ! -s "$TMP/rec.2" ]; then
    pass "poisoned ledger (null cost) refuses: exit 1, fake never launched"
else
    fail "poisoned ledger: rc=$RC rec=$(cat "$TMP/rec.2" 2>/dev/null) -- $(cat "$TMP/err.2")"
fi

# --- 3. Worktree = the shared checkout -> exit 2, never launched ----------
# Point HOME at a temp dir holding Scripts/Incursion so the real checkout is
# never touched.
FAKEHOME="$TMP/home"; mkdir -p "$FAKEHOME/Scripts/Incursion"
BRIEF="$TMP/brief3.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger3.jsonl"; : > "$LEDGER"
: > "$TMP/rec.3"
RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.3" \
    INCURSION_FAKE_MODE=success INCURSION_DEEPSEEK_KEY=canary-x \
    INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    "$WRAPPER" "$FAKEHOME/Scripts/Incursion" "$BRIEF" > "$TMP/out.3" 2> "$TMP/err.3"; echo $?)"
if [ "$RC" -eq 2 ] && [ ! -s "$TMP/rec.3" ]; then
    pass "shared checkout refused: exit 2, fake never launched"
else
    fail "shared checkout: rc=$RC rec=$(cat "$TMP/rec.3" 2>/dev/null) -- $(cat "$TMP/err.3")"
fi

# --- 4. Success with two step_finish events -> one row, sum, steps 2 ------
# HOME is a temp dir so the shared provider cache lands in the temp tree
# instead of the real ~/Library/Caches (which the check may not be able to
# write). The wrapper's own sandbox-exec cannot nest under the check's, so
# billing is measured here and the confinement assertion is 7.
FAKEHOME="$TMP/home4"; mkdir -p "$FAKEHOME"
WORK="$TMP/wt4"; mkdir -p "$WORK"
BRIEF="$TMP/brief4.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger4.jsonl"; : > "$LEDGER"
: > "$TMP/rec.4"
RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.4" INCURSION_FAKE_MODE=success \
    INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.4" 2> "$TMP/err.4"; echo $?)"
ROW_COUNT="$(wc -l < "$LEDGER" | tr -d ' ')"
if [ "$SANDBOX_OK" -eq 0 ]; then
    skip "success billing: not run (sandbox-exec cannot nest here)"
elif [ "$RC" -eq 0 ] && [ "$ROW_COUNT" -eq 1 ] \
    && grep -q '"cost":0.15' "$LEDGER" \
    && grep -q '"steps":2' "$LEDGER" \
    && grep -q '"harness":"opencode"' "$LEDGER" \
    && grep -q '"cost_source":"opencode-estimate"' "$LEDGER"; then
    pass "success bills one row: exit 0, cost 0.15, steps 2"
else
    fail "success billing: rc=$RC rows=$ROW_COUNT ledger=$(cat "$LEDGER" 2>/dev/null) -- $(cat "$TMP/err.4")"
fi

# --- 5. step_finish with tokens but no cost -> cost null, exit 2 ----------
FAKEHOME="$TMP/home5"; mkdir -p "$FAKEHOME"
WORK="$TMP/wt5"; mkdir -p "$WORK"
BRIEF="$TMP/brief5.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger5.jsonl"; : > "$LEDGER"
: > "$TMP/rec.5"
RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.5" INCURSION_FAKE_MODE=no-cost \
    INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.5" 2> "$TMP/err.5"; echo $?)"
if [ "$SANDBOX_OK" -eq 0 ]; then
    skip "tokens-with-no-cost poison: not run (sandbox-exec cannot nest here)"
elif [ "$RC" -eq 2 ] && [ "$(wc -l < "$LEDGER" | tr -d ' ')" -eq 1 ] \
    && grep -q '"cost":null' "$LEDGER"; then
    pass "tokens with no usable cost poisons the ledger: exit 2, null row"
else
    fail "no-cost poison: rc=$RC ledger=$(cat "$LEDGER" 2>/dev/null) -- $(cat "$TMP/err.5")"
fi

# --- 6. The fake sees the disable flags and the config path ---------------
# Reuse run 4's recording.
if [ "$SANDBOX_OK" -eq 0 ]; then
    skip "fake environment flags: not run (sandbox-exec cannot nest here)"
elif grep -q '^ENV OPENCODE_DISABLE_CLAUDE_CODE=1$' "$TMP/rec.4" \
    && grep -qF "ENV OPENCODE_CONFIG=$CONFIG" "$TMP/rec.4"; then
    pass "fake sees OPENCODE_DISABLE_CLAUDE_CODE=1 and the opencode.json config"
else
    fail "fake environment: $(cat "$TMP/rec.4" 2>/dev/null)"
fi

# --- 7. Sandbox confines writes to the worktree ---------------------------
# Runs inside sandbox-exec, which cannot nest, so under this check's own
# sandbox sandbox-exec itself will refuse to apply. That is reported, not
# weakened; the Claude session runs this check outside any sandbox.
FAKEHOME="$TMP/home7"; mkdir -p "$FAKEHOME"
WORK="$TMP/wt7"; mkdir -p "$WORK"
OUTSIDE="$REAL_HOME/.incursion-opencode-sandbox-probe-$$"; rm -f "$OUTSIDE"
PROBE_OUTSIDE="$OUTSIDE"
BRIEF="$TMP/brief7.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger7.jsonl"; : > "$LEDGER"
: > "$TMP/rec.7"
RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.7" INCURSION_FAKE_MODE=sandbox \
    INCURSION_FAKE_WORKDIR="$WORK" INCURSION_FAKE_OUTSIDE="$OUTSIDE" \
    INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.7" 2> "$TMP/err.7"; echo $?)"
if [ "$SANDBOX_OK" -eq 0 ]; then
    skip "sandbox confinement: not run (sandbox-exec cannot nest here)"
else
    INSIDE="$(grep -c 'WRITE INSIDE WORKDIR ok' "$TMP/rec.7" 2>/dev/null)"
    if [ "$RC" -eq 0 ] && [ ! -e "$OUTSIDE" ] && [ "$INSIDE" -ge 1 ]; then
        pass "sandbox: write outside WORKDIR/CACHEDIR fails, write inside succeeds"
    else
        fail "sandbox: rc=$RC outside-exists=$([ -e "$OUTSIDE" ] && echo yes || echo no) inside=$INSIDE -- $(cat "$TMP/err.7")"
    fi
fi

# --- 8. The canary key appears in no output, ledger or run-dir file -------
CANARY="canary-opencode-9b1e"
FAKEHOME="$TMP/home8"; mkdir -p "$FAKEHOME"
WORK="$TMP/wt8"; mkdir -p "$WORK"
BRIEF="$TMP/brief8.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger8.jsonl"; : > "$LEDGER"
: > "$TMP/rec.8"
RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.8" INCURSION_FAKE_MODE=success \
    INCURSION_DEEPSEEK_KEY="$CANARY" INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.8" 2> "$TMP/err.8"; echo $?)"
LEAK=0
grep -qF "$CANARY" "$TMP/out.8" && LEAK=1
grep -qF "$CANARY" "$TMP/err.8" && LEAK=1
grep -qF "$CANARY" "$LEDGER" && LEAK=1
if [ -d "$WORK/logs/opencode" ]; then
    grep -rqF "$CANARY" "$WORK/logs/opencode" && LEAK=1
fi
if [ "$LEAK" -eq 0 ]; then
    pass "the canary key reaches no stdout, stderr, ledger or run-dir file"
else
    fail "the canary key leaked"
fi

# --- 9. opencode.json parses and denies the guarded commands --------------
if python3 - "$CONFIG" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
perm = cfg["permission"]
assert perm["external_directory"] == "deny", "external_directory must be denied"
bash = perm["bash"]
assert bash["git *"] == "deny", "git * must be denied"
assert bash["bd *"] == "deny", "bd * must be denied"
assert bash["*"] == "allow", "* must be allowed"
PY
then
    pass "opencode.json parses and denies git *, bd * and external_directory"
else
    fail "opencode.json permission check"
fi

# --- 10. Read-only git is allowed, every other git command stays denied ---
# Models opencode's DOCUMENTED bash-rule precedence (opencode.ai/docs/
# permissions): patterns are wildcard-matched, and THE LAST MATCHING RULE
# WINS, `*` matching any characters. This is a model of that documented rule,
# NOT opencode itself: no opencode binary runs here. The same evaluator runs
# under --prove-red, where deleting the allow rules or `"git *": "deny"` must
# turn it red.
if python3 - "$CONFIG" <<'PY'
import json, re, sys

cfg = json.load(open(sys.argv[1]))
rules = list(cfg["permission"]["bash"].items())


def regex_for(pattern):
    out = "".join(".*" if ch == "*" else re.escape(ch) for ch in pattern)
    return re.compile("^" + out + "$")


compiled = [(regex_for(p), v) for p, v in rules]


def verdict(cmd):
    last = None
    for rx, v in compiled:
        if rx.match(cmd):
            last = v
    return last


allow = [
    "git status",
    "git status --porcelain",
    "git diff",
    "git diff --stat",
    "git log --oneline -3",
    "git show HEAD",
    "git ls-files tools",
    "git rev-parse HEAD",
]
deny = [
    "git commit -m x",
    "git add .",
    "git checkout -- f",
    "git reset --hard",
    "git push",
    "git stash",
    "git -C /x status",
    "bd ready",
    "gh pr list",
]

bad = []
for cmd in allow:
    got = verdict(cmd)
    if got != "allow":
        bad.append((cmd, "allow", got))
for cmd in deny:
    got = verdict(cmd)
    if got != "deny":
        bad.append((cmd, "deny", got))

if bad:
    for cmd, want, got in bad:
        print("  %-24s wanted %-5s got %s" % (cmd, want, got or "none"))
    sys.exit(1)
PY
then
    pass "read-only git allowed; all other git, bd and gh commands denied"
else
    fail "opencode.json bash rule precedence: read-only git / denied git"
fi

# --- 11. A harness that never writes is killed and billed as killed -------
# The wrapper's watchdog stops a zero-output run, and billing writes exactly
# one row with killed=startup and cost=0. This launches the harness, so under
# a nested sandbox it SKIPs (assertion 4's note applies).
FAKEHOME="$TMP/home11"; mkdir -p "$FAKEHOME"
WORK="$TMP/wt11"; mkdir -p "$WORK"
BRIEF="$TMP/brief11.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger11.jsonl"; : > "$LEDGER"
: > "$TMP/rec.11"
RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.11" INCURSION_FAKE_MODE=never \
    INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    INCURSION_WATCHDOG_STARTUP=2 INCURSION_WATCHDOG_POLL=1 INCURSION_WATCHDOG_GRACE=2 \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.11" 2> "$TMP/err.11"; echo $?)"
ROW_COUNT="$(wc -l < "$LEDGER" | tr -d ' ')"
RUNDIR_11_RAW="$(ls -d "$WORK"/logs/opencode/* 2>/dev/null | head -n 1)"
# The wrapper resolves the worktree with pwd -P (/var -> /private/var), so
# canonicalise before comparing against the path it printed.
RUNDIR_11=""
if [ -n "$RUNDIR_11_RAW" ]; then
    RUNDIR_11="$(cd "$RUNDIR_11_RAW" && pwd -P)"
fi
if [ "$SANDBOX_OK" -eq 0 ]; then
    skip "killed run billing: not run (sandbox-exec cannot nest here)"
elif [ "$RC" -eq 2 ] && [ "$ROW_COUNT" -eq 1 ] \
    && grep -q '"killed":"startup"' "$LEDGER" \
    && grep -q '"cost":0' "$LEDGER" \
    && grep -q 'startup' "$TMP/err.11" \
    && [ -n "$RUNDIR_11" ] && grep -qF "$RUNDIR_11" "$TMP/err.11"; then
    pass "killed run: exit 2 naming startup and the run dir, one row killed=startup cost=0"
else
    fail "killed run: rc=$RC rows=$ROW_COUNT rundir=$RUNDIR_11 ledger=$(cat "$LEDGER" 2>/dev/null) -- $(cat "$TMP/err.11")"
fi

# --- 12. A looping harness is stopped by the canary, billed killed=loop ----
# The fake emits a real loop step from tools/fixtures/opencode-loop/loop.jsonl
# and then sleeps; the idle limit is far away, so only the loop_check.py canary
# stops it. The wrapper exits 3, the row says killed=loop, the saved canary
# text is printed under the loop header, and the events copy lands under the
# runs dir the check redirected with INCURSION_OPENCODE_RUNS_DIR (never the
# real checkout's logs). This launches the harness, so under a nested sandbox
# it SKIPs (assertion 4's note applies).
LOOP_FIXTURE="$ROOT/tools/fixtures/opencode-loop/loop.jsonl"
CLEAN_FIXTURE="$ROOT/tools/fixtures/opencode-loop/clean.jsonl"
FAKEHOME="$TMP/home12"; mkdir -p "$FAKEHOME"
WORK="$TMP/wt12"; mkdir -p "$WORK"
BRIEF="$TMP/brief12.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger12.jsonl"; : > "$LEDGER"
RUNS12="$TMP/runs12"; mkdir -p "$RUNS12"
: > "$TMP/rec.12"
RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.12" \
    INCURSION_FAKE_MODE=loop INCURSION_FAKE_EVENTS="$LOOP_FIXTURE" \
    INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    INCURSION_OPENCODE_RUNS_DIR="$RUNS12" \
    INCURSION_WATCHDOG_STARTUP=5 INCURSION_WATCHDOG_IDLE=30 INCURSION_WATCHDOG_POLL=1 \
    INCURSION_WATCHDOG_GRACE=2 \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.12" 2> "$TMP/err.12"; echo $?)"
ROW_COUNT="$(wc -l < "$LEDGER" | tr -d ' ')"
COPY_12="$(ls "$RUNS12"/*.jsonl 2>/dev/null | head -n 1)"
if [ "$SANDBOX_OK" -eq 0 ]; then
    skip "loop stop: not run (sandbox-exec cannot nest here)"
elif [ "$RC" -eq 3 ] && [ "$ROW_COUNT" -eq 1 ] \
    && grep -q '"killed":"loop"' "$LEDGER" \
    && grep -q 'DeepSeek repetition loop: run stopped (inc-uxmf)' "$TMP/err.12" \
    && grep -q 'loop messageID=' "$TMP/err.12" \
    && [ -n "$COPY_12" ] && cmp -s "$COPY_12" "$LOOP_FIXTURE"; then
    pass "loop stop: exit 3, row killed=loop, canary text on stderr, events copied"
else
    fail "loop stop: rc=$RC rows=$ROW_COUNT copy=$COPY_12 ledger=$(cat "$LEDGER" 2>/dev/null) -- $(cat "$TMP/err.12")"
fi

# --- 13. Direct: loop_check.py exits 1 on loop.jsonl, 0 on clean.jsonl -----
# Runs everywhere, sandbox or not: loop_check.py never launches the harness.
LOOP_RC=0; CLEAN_RC=0
python3 "$ROOT/tools/opencode/loop_check.py" "$LOOP_FIXTURE" > "$TMP/loop13.out" 2>&1
LOOP_RC=$?
python3 "$ROOT/tools/opencode/loop_check.py" "$CLEAN_FIXTURE" > "$TMP/clean13.out" 2>&1
CLEAN_RC=$?
if [ "$LOOP_RC" -eq 1 ] && grep -q '^loop messageID=' "$TMP/loop13.out" \
    && [ "$CLEAN_RC" -eq 0 ] && [ ! -s "$TMP/clean13.out" ]; then
    pass "loop_check: loop.jsonl exits 1 with a loop line, clean.jsonl exits 0 silently"
else
    fail "loop_check: loop rc=$LOOP_RC clean rc=$CLEAN_RC -- $(cat "$TMP/loop13.out") $(cat "$TMP/clean13.out")"
fi

if [ "$FAIL" -eq 0 ] && [ "$SKIP_COUNT" -eq 0 ]; then
    echo "PASS: check_opencode_ds.sh, all thirteen assertions"
    exit 0
elif [ "$FAIL" -eq 0 ]; then
    echo "PASS (partial): check_opencode_ds.sh, $SKIP_COUNT assertion(s) skipped and not counted;"
    echo "                rerun outside any sandbox to run all thirteen (exit 2 = incomplete)"
    exit 2
else
    echo "FAIL: check_opencode_ds.sh, at least one assertion failed above"
    exit 1
fi
