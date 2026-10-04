#!/bin/bash
# gate: cheap
# gate-serial: race wall-clock watchdog/proxy/stream deadlines; CPU load could flip them
#
# Does tools/opencode_ds.sh refuse the shared checkout, bill exactly one
# ledger row for a successful harness run (cost = the sum of its step_finish
# costs, steps = the count), poison the ledger when opencode quotes tokens but
# no usable cost, keep the API key out of every file it writes, confine
# opencode to the worktree with the Seatbelt profile, stop a harness that
# never writes -- billing it as one killed=startup row at cost 0 -- and stop a
# harness stuck in a DeepSeek repetition loop via the loop_check.py canary,
# billing it as one killed=loop row at exit 3 and copying its run dir aside,
# and stop a harness whose step context passed the loop_check.py ceiling via
# the same canary, billing it as one killed=context row at exit 4?
# Also that tools/opencode/record_proxy.py forwards a POST byte-for-byte,
# records request/response/meta, streams a chunked reply before upstream
# finishes, relays the Authorization header without writing it to any file,
# and that the wrapper wires it in (one recorded request, no proxy left
# running) and, on a loop kill, copies the run dir including requests/.
# Defends beads inc-h1bq, inc-gofz, inc-uxmf and inc-oehi: the opencode rung of
# the implementer ladder must never touch the shared checkout, must not hang
# its dispatcher when the harness stalls, must not burn tokens on a loop, and
# must keep the exact request of a looping run so it can be replayed. Directly
# checks loop_check.py catches all three loop shapes: repeated short lines
# (tools/fixtures/opencode-loop/loop.jsonl), a step that printed native
# tool-call markup as text (tools/opencode/fixtures/markup-dsml.jsonl), and one
# line of any length repeated many times (tools/opencode/fixtures/
# one-line-loop.jsonl) -- the last two trimmed from the real captures that the
# first rule missed -- and its context-ceiling rule
# (tools/opencode/fixtures/context-over.jsonl, inc-xiqb).
#
# Fully offline. A fake `opencode` written into the temp dir stands in for the
# real harness via INCURSION_OPENCODE_BIN; it records its argv and environment
# and emits scripted events.jsonl (the loop case cats
# tools/fixtures/opencode-loop/loop.jsonl). A fake upstream (a tiny stdlib
# HTTP server) stands in for DeepInfra via INCURSION_DS_UPSTREAM. No network
# request ever leaves this machine.
#
#   tools/check_opencode_ds.sh               run every assertion (numbered,
#                                            with 13b's six and 13c's
#                                            three loop_check sub-checks)
#   tools/check_opencode_ds.sh --prove-red   mutate the
#                                            sandbox prefix, the JSON bash
#                                            rules, MIN_REPEATED_LINES,
#                                            MIN_SAME_LINE, the markup rule, the
#                                            context ceiling, the proxy's
#                                            request write and the brief's
#                                            preamble prepend, confirm red
#
# Exit: 0 pass, 1 fail, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="$ROOT/tools/opencode_ds.sh"
CONFIG="$ROOT/tools/opencode/opencode.json"
PROFILE="$ROOT/tools/opencode/sandbox.sb"
PROXY="$ROOT/tools/opencode/record_proxy.py"
PREAMBLE="$ROOT/tools/opencode/brief_preamble.md"

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
BACKUP_PROXY=""

cleanup() {
    # stop_upstream is defined below but this trap is set before it; guard.
    if declare -F stop_upstream >/dev/null 2>&1; then
        stop_upstream
    fi
    if [ -n "${PROXY_PIDS:-}" ]; then
        for p in $PROXY_PIDS; do kill -KILL "$p" 2>/dev/null; done
    fi
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
    if [ -n "$BACKUP_PROXY" ] && [ -f "$BACKUP_PROXY" ]; then
        cp "$BACKUP_PROXY" "$PROXY"
        if cmp -s "$BACKUP_PROXY" "$PROXY"; then
            echo "restored tools/opencode/record_proxy.py byte-identical to its original"
        else
            echo "COULD NOT CONFIRM record_proxy.py WAS RESTORED -- check it by hand" >&2
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
# Handled FIRST, before the assertions below ever run. Each mutation restores
# the file it touches: (b) drop the `sandbox-exec` prefix, so assertion 7 must
# go red; (c) strip the read-only-git allow rules from opencode.json, so
# assertion 10 must go red; (d) drop `"git *": "deny"` from opencode.json, so
# assertion 10 must go red; (e) raise loop_check.py's MIN_REPEATED_LINES, so
# assertion 13 must go red; (f) remove the proxy's request-file write, so
# assertion 14 must go red; (g) raise loop_check.py's MIN_SAME_LINE, so
# assertion 13b's F3 check must go red; (h) disable loop_check.py's markup rule,
# so assertion 13b's F2 check must go red; (j) remove the brief preamble
# prepend, so assertion 6b must go red. Original files are restored, and each
# restoration verified byte-identical with cmp, by the EXIT trap above.
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

    # (e) loop_check.py's MIN_REPEATED_LINES raised out of reach, so the real
    # loop fixture must no longer be called a loop and assertion 13 must go red.
    # The loop fixture also trips rule 3 (one line repeated 66 times), so rule 3
    # is raised out of reach too; otherwise it would mask rule 1 and leave
    # assertion 13 green. The point of this mutation is that rule 1 is
    # load-bearing, so it must be the one disqualifying the fixture.
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
src = src.replace(needle, "MIN_REPEATED_LINES = 10000", 1)
src = src.replace("MIN_SAME_LINE = 40", "MIN_SAME_LINE = 10000", 1)
open(path, "w").write(src)
PY
    echo "mutated tools/opencode/loop_check.py: MIN_REPEATED_LINES = 10000 (and MIN_SAME_LINE raised, to isolate rule 1)"
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

    # (f) the proxy's request-file write removed, so it records no
    # NNNN.request.json. Assertion 14's byte-identical comparison must go red.
    # Direct proxy only, so this proof runs in any environment.
    BACKUP_PROXY="$TMP/record_proxy.py.orig"
    cp "$PROXY" "$BACKUP_PROXY"
    NEEDLE='            fh.write(body)'
    if ! grep -qF "$NEEDLE" "$PROXY"; then
        echo "could not find the request-file write to mutate: $NEEDLE" >&2
        exit 2
    fi
    python3 - "$PROXY" "$NEEDLE" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path).read()
open(path, "w").write(src.replace(needle, "            pass  # MUTATED by --prove-red", 1))
PY
    echo "mutated tools/opencode/record_proxy.py: request file never written"
    MUT_OUT="$("$ROOT/tools/check_opencode_ds.sh" 2>&1)"
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ] && grep -q "FAIL.*proxy forward" <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion 14 (byte-identical request file) went red"
    else
        echo "FAIL: assertion 14 stayed green with the request write removed (rc=$MUT_RC)"
        echo "$MUT_OUT" | tail -20
        PROVE_FAIL=1
    fi
    cp "$BACKUP_PROXY" "$PROXY"
    cmp -s "$BACKUP_PROXY" "$PROXY" || { echo "restore of record_proxy.py failed" >&2; exit 2; }

    # (g) loop_check.py's MIN_SAME_LINE raised out of reach, so the F3 fixture
    # must no longer be called a one-line loop and assertion 13b's F3 check
    # must go red. Restored byte-identical below.
    BACKUP_LOOP="$TMP/loop_check.py.same.orig"
    cp "$LOOP_CHECK" "$BACKUP_LOOP"
    NEEDLE='MIN_SAME_LINE = 40'
    if ! grep -qF "$NEEDLE" "$LOOP_CHECK"; then
        echo "could not find MIN_SAME_LINE to mutate" >&2
        exit 2
    fi
    python3 - "$LOOP_CHECK" "$NEEDLE" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path).read()
open(path, "w").write(src.replace(needle, "MIN_SAME_LINE = 10000", 1))
PY
    echo "mutated tools/opencode/loop_check.py: MIN_SAME_LINE = 10000"
    MUT_OUT="$("$ROOT/tools/check_opencode_ds.sh" 2>&1)"
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ] && grep -q 'FAIL.*loop_check (F3)' <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion 13b (F3 one-line loop) went red"
    else
        echo "FAIL: assertion 13b (F3) stayed green with MIN_SAME_LINE = 10000 (rc=$MUT_RC)"
        echo "$MUT_OUT" | tail -20
        PROVE_FAIL=1
    fi
    cp "$BACKUP_LOOP" "$LOOP_CHECK"
    cmp -s "$BACKUP_LOOP" "$LOOP_CHECK" || { echo "restore of loop_check.py failed" >&2; exit 2; }

    # (h) loop_check.py's DSML markup rule removed, so the F2 fixture must no
    # longer be flagged and assertion 13b's markup check must go red.
    BACKUP_LOOP="$TMP/loop_check.py.dsml.orig"
    cp "$LOOP_CHECK" "$BACKUP_LOOP"
    NEEDLE='TOOL_MARKUP_OPEN = "<\uFF5CDSML\uFF5C"'
    NEEDLE_CLOSE='TOOL_MARKUP_CLOSE = "</\uFF5C"'
    if ! grep -qF "$NEEDLE" "$LOOP_CHECK" || ! grep -qF "$NEEDLE_CLOSE" "$LOOP_CHECK"; then
        echo "could not find the markup tokens to mutate" >&2
        exit 2
    fi
    python3 - "$LOOP_CHECK" "$NEEDLE" "$NEEDLE_CLOSE" <<'PY'
import sys
path, needle, needle_close = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
src = src.replace(needle, 'TOOL_MARKUP_OPEN = "MUTATED-NEVER-MATCHES"', 1)
src = src.replace(needle_close, 'TOOL_MARKUP_CLOSE = "MUTATED-NEVER-MATCHES"', 1)
open(path, "w").write(src)
PY
    echo "mutated tools/opencode/loop_check.py: markup rule disabled"
    MUT_OUT="$("$ROOT/tools/check_opencode_ds.sh" 2>&1)"
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ] && grep -q 'FAIL.*loop_check (F2)' <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion 13b (F2 markup) went red"
    else
        echo "FAIL: assertion 13b (F2) stayed green with the markup rule removed (rc=$MUT_RC)"
        echo "$MUT_OUT" | tail -20
        PROVE_FAIL=1
    fi
    cp "$BACKUP_LOOP" "$LOOP_CHECK"
    cmp -s "$BACKUP_LOOP" "$LOOP_CHECK" || { echo "restore of loop_check.py failed" >&2; exit 2; }

    # (i) loop_check.py's context ceiling raised out of reach (10**12), so the
    # context-over fixture must no longer be flagged and assertion 13c's F4
    # check must go red. The env override is unset in that mutated run by
    # raising the default constant; sub-check (a) uses the default ceiling.
    # Restored byte-identical below.
    BACKUP_LOOP="$TMP/loop_check.py.context.orig"
    cp "$LOOP_CHECK" "$BACKUP_LOOP"
    NEEDLE='CONTEXT_CEILING = 100000'
    if ! grep -qF "$NEEDLE" "$LOOP_CHECK"; then
        echo "could not find CONTEXT_CEILING to mutate" >&2
        exit 2
    fi
    python3 - "$LOOP_CHECK" "$NEEDLE" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path).read()
open(path, "w").write(src.replace(needle, "CONTEXT_CEILING = 10**12", 1))
PY
    echo "mutated tools/opencode/loop_check.py: CONTEXT_CEILING = 10**12"
    MUT_OUT="$("$ROOT/tools/check_opencode_ds.sh" 2>&1)"
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ] && grep -q 'FAIL.*loop_check (F4)' <<< "$MUT_OUT"; then
        echo "PASS (as intended): assertion 13c (F4 context ceiling) went red"
    else
        echo "FAIL: assertion 13c (F4) stayed green with CONTEXT_CEILING = 10**12 (rc=$MUT_RC)"
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
        if [ "$PROVE_FAIL" -eq 0 ]; then
            echo "INCONCLUSIVE: earlier mutations proven; mutation (b) needs an unsandboxed run"
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

    # (j) the preamble prepend removed, so the wrapper sends the brief alone.
    # Assertion 6b (the argv preamble check) must go red. It reuses run 4,
    # which launches the harness, so this proof needs an unsandboxed run.
    if [ "$SANDBOX_RUNNABLE" -eq 0 ]; then
        echo "SKIP (j): sandbox-exec cannot run inside this sandbox, so"
        echo "          assertion 6b cannot launch the harness to go red."
    else
        BACKUP_PRE="$TMP/opencode_ds.sh.preamble.orig"
        cp "$WRAPPER" "$BACKUP_PRE"
        NEEDLE_PRE='BRIEF_TEXT="$(cat "$PREAMBLE_FILE")"$'"'"'\n\n---\n\n'"'"'"$(cat "$BRIEF_FILE")"'
        if ! grep -qF "$NEEDLE_PRE" "$WRAPPER"; then
            echo "could not find the brief prepend to mutate" >&2
            exit 2
        fi
        python3 - "$WRAPPER" "$NEEDLE_PRE" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path).read()
replacement = 'BRIEF_TEXT="$(cat "$BRIEF_FILE")"  # MUTATED by --prove-red'
open(path, "w").write(src.replace(needle, replacement, 1))
PY
        echo "mutated tools/opencode_ds.sh: brief preamble prepend removed"
        MUT_OUT="$("$ROOT/tools/check_opencode_ds.sh" 2>&1)"
        MUT_RC=$?
        if [ "$MUT_RC" -ne 0 ] && grep -q "FAIL.*preamble-prefixed brief" <<< "$MUT_OUT"; then
            echo "PASS (as intended): assertion 6b (preamble-prefixed brief) went red"
        else
            echo "FAIL: assertion 6b stayed green with the prepend removed (rc=$MUT_RC)"
            echo "$MUT_OUT" | tail -20
            PROVE_FAIL=1
        fi
        cp "$BACKUP_PRE" "$WRAPPER"
        cmp -s "$BACKUP_PRE" "$WRAPPER" || { echo "restore of opencode_ds.sh failed" >&2; exit 2; }
    fi

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
    printf 'ENV INCURSION_DS_BASEURL=%s\n' "${INCURSION_DS_BASEURL:-}"
} >> "$REC"

# When told, make one real HTTP POST to the model endpoint the wrapper pointed
# us at ($INCURSION_DS_BASEURL, the recording proxy) and record its status and
# body. This is what proves the wrapper's proxy is wired end to end.
if [ -n "${INCURSION_FAKE_POST:-}" ]; then
    python3 - "${INCURSION_DS_BASEURL:-}" "${INCURSION_FAKE_HTTP_OUT:-/dev/null}" <<'PY'
import sys, urllib.request
base, out = sys.argv[1], sys.argv[2]
req = urllib.request.Request(
    base + "/chat/completions",
    data=b'{"model":"m","stream":true}',
    headers={"Content-Type": "application/json",
             "Authorization": "Bearer SENTINEL-KEY-123"},
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = resp.read()
        status = resp.status
except Exception as exc:  # noqa: BLE001 -- recorded, not raised
    body = str(exc).encode()
    status = -1
with open(out, "wb") as fh:
    fh.write(("STATUS %d\n" % status).encode())
    fh.write(body)
PY
fi

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
    context)
        # Emit a step_finish whose context (input + cache.read + cache.write)
        # is over the ceiling, then keep the harness alive so the watchdog's
        # canary (loop_check.py) fires on the context rule.
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

# --- fake upstream --------------------------------------------------------
# A tiny stdlib HTTP server that stands in for DeepInfra, pointed to by
# INCURSION_DS_UPSTREAM. It binds 127.0.0.1:0, writes its port to argv[1] (temp
# then rename, like the proxy), and appends every request's path and
# Authorization header to argv[2]. FU_MODE=plain returns a fixed JSON body;
# FU_MODE=stream sends one chunk, sleeps FU_SLEEP seconds, then a second, so
# the proxy's streaming can be timed. It holds no key of its own.
UPSTREAM="$TMP/fake_upstream.py"
cat > "$UPSTREAM" <<'UP_EOF'
import http.server, os, sys, time

port_file, hits_file = sys.argv[1], sys.argv[2]
MODE = os.environ.get("FU_MODE", "plain")
SLEEP = float(os.environ.get("FU_SLEEP", "2"))


def chunk(b):
    return ("%x\r\n" % len(b)).encode() + b + b"\r\n"


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        with open(hits_file, "a", encoding="utf-8") as fh:
            fh.write("PATH %s\n" % self.path)
            fh.write("AUTH %s\n" % self.headers.get("Authorization", ""))
            fh.write("BODY %d\n" % len(body))
        if MODE == "stream":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            self.wfile.write(chunk(b"data: first\n\n"))
            self.wfile.flush()
            time.sleep(SLEEP)
            self.wfile.write(chunk(b"data: second\n\n"))
            self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
            return
        payload = b'{"id":"up","choices":[{"message":{"content":"up"}}]}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
        self.wfile.flush()


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(port_file + ".tmp", "w", encoding="utf-8") as fh:
    fh.write(str(srv.server_address[1]))
os.replace(port_file + ".tmp", port_file)
srv.serve_forever()
UP_EOF

# start_upstream sets globals FU_PID, FU_HITS and FU_PORT (call it plainly,
# never in a command substitution, or the assignments land in a subshell). An
# empty FU_PORT means the upstream did not bind in time.
FU_PID=""
FU_HITS=""
FU_PORT=""
UPSTREAM_PIDS=""
start_upstream() {
    local mode="$1" sleep_s="$2"
    local pf="$TMP/up.port.$RANDOM" hf="$TMP/up.hits.$RANDOM"
    rm -f "$pf"
    FU_MODE="$mode" FU_SLEEP="$sleep_s" python3 "$UPSTREAM" "$pf" "$hf" \
        > "$TMP/up.log" 2>&1 &
    FU_PID=$!
    UPSTREAM_PIDS="$UPSTREAM_PIDS $FU_PID"
    local waited=0
    while [ "$waited" -lt 100 ]; do
        [ -f "$pf" ] && break
        sleep 0.1
        waited=$((waited + 1))
    done
    FU_HITS="$hf"
    FU_PORT=""
    if [ -f "$pf" ]; then
        FU_PORT="$(head -n 1 "$pf" | tr -d '[:space:]')"
    fi
}
stop_upstream() {
    if [ -n "$FU_PID" ] && kill -0 "$FU_PID" 2>/dev/null; then
        kill -KILL "$FU_PID" 2>/dev/null
        wait "$FU_PID" 2>/dev/null
    fi
    FU_PID=""
}

# --- recording proxy under test -------------------------------------------
# start_proxy sets globals PROXY_PID and PROXY_PORT (call it plainly, never in
# a command substitution, or the assignments land in a subshell). An empty
# PROXY_PORT means the proxy did not bind in time. INCURSION_DS_UPSTREAM must
# name the fake upstream.
PROXY_PIDS=""
PROXY_PID=""
PROXY_PORT=""
start_proxy() {
    local rec="$1"
    local pf="$TMP/proxy.port.$RANDOM"
    rm -f "$pf"
    python3 "$PROXY" --dir "$rec" --port-file "$pf" > "$TMP/proxy.log" 2>&1 &
    PROXY_PID=$!
    PROXY_PIDS="$PROXY_PIDS $PROXY_PID"
    local waited=0
    while [ "$waited" -lt 100 ]; do
        [ -f "$pf" ] && break
        sleep 0.1
        waited=$((waited + 1))
    done
    PROXY_PORT=""
    if [ -f "$pf" ]; then
        PROXY_PORT="$(head -n 1 "$pf" | tr -d '[:space:]')"
    fi
}
stop_proxy_direct() {
    if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
        kill -TERM "$PROXY_PID" 2>/dev/null
        wait "$PROXY_PID" 2>/dev/null
    fi
    PROXY_PID=""
    PROXY_PORT=""
}

# --- sandbox availability probe ------------------------------------------
# sandbox-exec cannot nest: inside another Seatbelt sandbox (a Claude session
# running this check), `sandbox-exec` itself refuses to apply and exits 71.
# The assertions that need to LAUNCH the harness (4, 5, 6, 6b, 7, 11, 12, 12b,
# 17, 18) cannot run in that environment. Detect it once and report those as
# SKIP; outside any sandbox they all run. Assertions 3, 3b, 8, 9, 10 and
# the direct-proxy 13, 13b, 13c, 14, 15, 16 never launch the harness.
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
    echo "      assertions 4, 5, 6, 6b, 7, 11, 12, 17 and 18 are reported SKIP here and"
    echo "      must be run outside any sandbox (the Claude session will do so)."
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

# --- 3b. Missing preamble -> exit 2, never launched, no ledger row ---------
# INCURSION_DS_PREAMBLE points the wrapper at a non-existent path, so the
# refusal must fire BEFORE any spend or launch. The real preamble file is
# never edited or moved.
WORK="$TMP/wt3b"; mkdir -p "$WORK"
BRIEF="$TMP/brief3b.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger3b.jsonl"; : > "$LEDGER"
: > "$TMP/rec.3b"
RC="$(INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.3b" INCURSION_FAKE_MODE=success \
    INCURSION_DS_PREAMBLE="$TMP/does-not-exist-preamble.md" \
    INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.3b" 2> "$TMP/err.3b"; echo $?)"
if [ "$RC" -eq 2 ] && grep -q "brief preamble missing" "$TMP/err.3b" \
    && [ ! -s "$TMP/rec.3b" ] && [ ! -s "$LEDGER" ]; then
    pass "missing preamble refused: exit 2, fake never launched, no ledger row"
else
    fail "missing preamble: rc=$RC rec=$(cat "$TMP/rec.3b" 2>/dev/null) ledger=$(cat "$LEDGER" 2>/dev/null) -- $(cat "$TMP/err.3b")"
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

# --- 6b. The brief argument carries the preamble, then ---, then the brief --
# Reuse run 4's recording. The fake records each argv word as a line
# "ARG <value>", then its ENV lines; a multi-line brief makes every line up to
# the first "ENV " line part of the last ARG. The preamble's first line must
# start the value, it must contain a lone "---" separator, and it must end
# with the caller's brief text.
if [ "$SANDBOX_OK" -eq 0 ]; then
    skip "preamble-prefixed brief: not run (sandbox-exec cannot nest here)"
else
    PRE_OUT="$(python3 - "$TMP/rec.4" "$BRIEF" "$PREAMBLE" <<'PY'
import sys
rec, brief_path, preamble_path = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(rec, encoding="utf-8", errors="replace").read().splitlines()
start = None
for i, line in enumerate(lines):
    if line.startswith("ARG "):
        start = i
if start is None:
    print("NO_ARG")
    sys.exit(0)
# The brief value runs from the last ARG line to the first following ENV line.
end = len(lines)
for i in range(start + 1, len(lines)):
    if lines[i].startswith("ENV "):
        end = i
        break
value = "\n".join(lines[start:end])[len("ARG "):]
# The wrapper passes the brief via "$(cat ...)", which strips trailing
# newlines; mirror that so the tail comparison is exact.
brief = open(brief_path, encoding="utf-8").read().rstrip("\n")
first = open(preamble_path, encoding="utf-8").readline().rstrip("\n")
ok_first = value.startswith(first)
ok_sep = "\n---\n" in value
ok_end = value.endswith(brief)
print("OK" if (ok_first and ok_sep and ok_end) else
      "BAD first=%s sep=%s end=%s" % (ok_first, ok_sep, ok_end))
PY
)"
    if [ "$PRE_OUT" = "OK" ]; then
        pass "brief argument is the preamble, then ---, then the caller's brief"
    else
        fail "preamble-prefixed brief: $PRE_OUT"
    fi
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
# text is printed under the loop header, and the whole run dir (whose
# events.jsonl is the fixture) lands under the runs dir the check redirected
# with INCURSION_OPENCODE_RUNS_DIR (never the real checkout's logs). This
# launches the harness, so under a nested sandbox it SKIPs (assertion 4's note
# applies).
LOOP_FIXTURE="$ROOT/tools/fixtures/opencode-loop/loop.jsonl"
CLEAN_FIXTURE="$ROOT/tools/fixtures/opencode-loop/clean.jsonl"
FAKEHOME="$TMP/home12"; mkdir -p "$FAKEHOME"
WORK="$TMP/wt12"; mkdir -p "$WORK"
BRIEF="$TMP/brief12.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger12.jsonl"; : > "$LEDGER"
RUNS12="$TMP/runs12"; mkdir -p "$RUNS12"
: > "$TMP/rec.12"
# The loop fixture passes 100K context before its loop step, so raise the ceiling to isolate the loop rule.
RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.12" \
    INCURSION_FAKE_MODE=loop INCURSION_FAKE_EVENTS="$LOOP_FIXTURE" \
    INCURSION_DS_CONTEXT_CEILING=1000000000000 \
    INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    INCURSION_OPENCODE_RUNS_DIR="$RUNS12" \
    INCURSION_WATCHDOG_STARTUP=5 INCURSION_WATCHDOG_IDLE=30 INCURSION_WATCHDOG_POLL=1 \
    INCURSION_WATCHDOG_GRACE=2 \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.12" 2> "$TMP/err.12"; echo $?)"
ROW_COUNT="$(wc -l < "$LEDGER" | tr -d ' ')"
COPY_12="$(ls -d "$RUNS12"/*/ 2>/dev/null | head -n 1)"
COPY_12_EVENTS=""
[ -n "$COPY_12" ] && COPY_12_EVENTS="$COPY_12/events.jsonl"
if [ "$SANDBOX_OK" -eq 0 ]; then
    skip "loop stop: not run (sandbox-exec cannot nest here)"
elif [ "$RC" -eq 3 ] && [ "$ROW_COUNT" -eq 1 ] \
    && grep -q '"killed":"loop"' "$LEDGER" \
    && grep -q 'DeepSeek repetition loop: run stopped (inc-uxmf)' "$TMP/err.12" \
    && grep -q 'loop messageID=' "$TMP/err.12" \
    && [ -f "$COPY_12_EVENTS" ] && cmp -s "$COPY_12_EVENTS" "$LOOP_FIXTURE"; then
    pass "loop stop: exit 3, row killed=loop, canary text on stderr, run dir copied"
else
    fail "loop stop: rc=$RC rows=$ROW_COUNT copy=$COPY_12 ledger=$(cat "$LEDGER" 2>/dev/null) -- $(cat "$TMP/err.12")"
fi

# --- 12b. A run over the context ceiling is stopped, billed killed=context -
# The fake emits a step_finish whose context is over the ceiling and then
# sleeps; only the loop_check.py canary stops it. The wrapper exits 4, the row
# says killed=context (exactly one row), and stderr names the context ceiling.
# Launches the harness, so under a nested sandbox it SKIPs (as assertion 4).
CONTEXT_FIXTURE="$ROOT/tools/opencode/fixtures/context-over.jsonl"
FAKEHOME="$TMP/home12b"; mkdir -p "$FAKEHOME"
WORK="$TMP/wt12b"; mkdir -p "$WORK"
BRIEF="$TMP/brief12b.txt"; echo "do a thing" > "$BRIEF"
LEDGER="$TMP/ledger12b.jsonl"; : > "$LEDGER"
RUNS12B="$TMP/runs12b"; mkdir -p "$RUNS12B"
: > "$TMP/rec.12b"
RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.12b" \
    INCURSION_FAKE_MODE=context INCURSION_FAKE_EVENTS="$CONTEXT_FIXTURE" \
    INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
    INCURSION_OPENCODE_RUNS_DIR="$RUNS12B" \
    INCURSION_WATCHDOG_STARTUP=5 INCURSION_WATCHDOG_IDLE=30 INCURSION_WATCHDOG_POLL=1 \
    INCURSION_WATCHDOG_GRACE=2 \
    "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.12b" 2> "$TMP/err.12b"; echo $?)"
ROW_COUNT="$(wc -l < "$LEDGER" | tr -d ' ')"
if [ "$SANDBOX_OK" -eq 0 ]; then
    skip "context stop: not run (sandbox-exec cannot nest here)"
elif [ "$RC" -eq 4 ] && [ "$ROW_COUNT" -eq 1 ] \
    && grep -q '"killed":"context"' "$LEDGER" \
    && grep -q 'context ceiling' "$TMP/err.12b" \
    && grep -q '^context ' "$TMP/err.12b"; then
    pass "context stop: exit 4, one row killed=context, context ceiling on stderr"
else
    fail "context stop: rc=$RC rows=$ROW_COUNT ledger=$(cat "$LEDGER" 2>/dev/null) -- $(cat "$TMP/err.12b")"
fi

# --- 13. Direct: loop_check.py exits 1 on loop.jsonl, 0 on clean.jsonl -----
# Runs everywhere, sandbox or not: loop_check.py never launches the harness.
# clean.jsonl is a real capture whose context grows past 100000, so the loop
# rules are exercised here with the context ceiling raised out of the way; the
# ceiling itself is proven by assertion 13c. This keeps the assertion about the
# loop rules, not about context.
LOOP_RC=0; CLEAN_RC=0
INCURSION_DS_CONTEXT_CEILING=1000000000000 python3 "$ROOT/tools/opencode/loop_check.py" "$LOOP_FIXTURE" > "$TMP/loop13.out" 2>&1
LOOP_RC=$?
INCURSION_DS_CONTEXT_CEILING=1000000000000 python3 "$ROOT/tools/opencode/loop_check.py" "$CLEAN_FIXTURE" > "$TMP/clean13.out" 2>&1
CLEAN_RC=$?
if [ "$LOOP_RC" -eq 1 ] && grep -q '^loop messageID=' "$TMP/loop13.out" \
    && [ "$CLEAN_RC" -eq 0 ] && [ ! -s "$TMP/clean13.out" ]; then
    pass "loop_check: loop.jsonl exits 1 with a loop line, clean.jsonl exits 0 silently"
else
    fail "loop_check: loop rc=$LOOP_RC clean rc=$CLEAN_RC -- $(cat "$TMP/loop13.out") $(cat "$TMP/clean13.out")"
fi

# --- 13b. Direct: loop_check.py catches the two missed DeepSeek failures ---
# Runs everywhere, sandbox or not. The F2 and F3 fixtures are trimmed extracts
# of the real captured events (docs/evidence/inc-w431) that today's rules
# missed: F2 printed the model's native tool-call markup as text, and F3
# repeated one line 72 times in one step. Four synthetic steps prove the guards
# and their limits: a 100-line repeat under the token floor stays green, markup
# inside a code fence stays green, prose that mentions the bare substring "DSML"
# stays green, and prose that quotes the full markup token inline in backticks --
# as an earlier false positive did -- stays green.
MARKUP_FIXTURE="$ROOT/tools/opencode/fixtures/markup-dsml.jsonl"
ONELINE_FIXTURE="$ROOT/tools/opencode/fixtures/one-line-loop.jsonl"

python3 - "$TMP/lowtokens.jsonl" "$TMP/fenced-dsml.jsonl" "$TMP/prose-dsml.jsonl" "$TMP/inline-dsml.jsonl" <<'PY'
import json, sys

low, fenced, prose, inline = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]


def write(path, mid, text, output):
    with open(path, "w") as fh:
        fh.write(json.dumps({"type": "step_start", "part": {"messageID": mid}}) + "\n")
        fh.write(json.dumps({"type": "text", "part": {"messageID": mid, "text": text}}) + "\n")
        fh.write(json.dumps({"type": "step_finish",
                             "part": {"messageID": mid,
                                      "tokens": {"output": output}}}) + "\n")


# 100 repeats of one line, but only 1500 output tokens: under MIN_OUTPUT_TOKENS.
write(low, "msg_lowtokens", ("same repeated line here\n" * 100), 1500)
# The markup token inside a ``` fence only: stripped before the markup check.
write(fenced, "msg_fenced", "prose\n```\n<\uFF5CDSML\uFF5Cinvoke>x</invoke>\n```\nmore prose\n", 2500)
# Plain prose that mentions the bare substring "DSML" and "DSML=True" outside
# any fence, 500 output tokens: not a leak, must stay green.
write(prose, "msg_prose", "I saw the DSML substring in the text and DSML=True.\n", 500)
# Prose that quotes the full markup token inline in backticks, 500 output
# tokens: the token does not start a line, so it is prose, not a leak.
write(inline, "msg_inline", "Look at line 2: `<\uFF5CDSML\uFF5C parameter` and `</\uFF5C parameter>`.\n", 500)
PY

MARKUP_RC=0; ONELINE_RC=0; LOW_RC=0; FENCED_RC=0; PROSE_RC=0; INLINE_RC=0
python3 "$ROOT/tools/opencode/loop_check.py" "$MARKUP_FIXTURE" > "$TMP/markup13.out" 2>&1
MARKUP_RC=$?
python3 "$ROOT/tools/opencode/loop_check.py" "$ONELINE_FIXTURE" > "$TMP/oneline13.out" 2>&1
ONELINE_RC=$?
python3 "$ROOT/tools/opencode/loop_check.py" "$TMP/lowtokens.jsonl" > "$TMP/lowtokens13.out" 2>&1
LOW_RC=$?
python3 "$ROOT/tools/opencode/loop_check.py" "$TMP/fenced-dsml.jsonl" > "$TMP/fenced13.out" 2>&1
FENCED_RC=$?
python3 "$ROOT/tools/opencode/loop_check.py" "$TMP/prose-dsml.jsonl" > "$TMP/prose13.out" 2>&1
PROSE_RC=$?
python3 "$ROOT/tools/opencode/loop_check.py" "$TMP/inline-dsml.jsonl" > "$TMP/inline13.out" 2>&1
INLINE_RC=$?

if [ "$MARKUP_RC" -eq 1 ] && grep -q '^markup ' "$TMP/markup13.out"; then
    pass "loop_check (F2): native tool-call markup exits 1 with a markup line"
else
    fail "loop_check (F2): rc=$MARKUP_RC -- $(cat "$TMP/markup13.out")"
fi

if [ "$ONELINE_RC" -eq 1 ] && grep -q '^loop ' "$TMP/oneline13.out" \
    && grep -q 'same_line=' "$TMP/oneline13.out"; then
    pass "loop_check (F3): one line repeated 72x exits 1 with a same_line loop line"
else
    fail "loop_check (F3): rc=$ONELINE_RC -- $(cat "$TMP/oneline13.out")"
fi

if [ "$LOW_RC" -eq 0 ] && [ ! -s "$TMP/lowtokens13.out" ]; then
    pass "loop_check: 100 repeats under the 2000-token floor exits 0 silently"
else
    fail "loop_check low-tokens: rc=$LOW_RC -- $(cat "$TMP/lowtokens13.out")"
fi

if [ "$FENCED_RC" -eq 0 ] && [ ! -s "$TMP/fenced13.out" ]; then
    pass "loop_check: DSML only inside a code fence exits 0 silently"
else
    fail "loop_check fenced-markup: rc=$FENCED_RC -- $(cat "$TMP/fenced13.out")"
fi

if [ "$PROSE_RC" -eq 0 ] && [ ! -s "$TMP/prose13.out" ]; then
    pass "loop_check: prose mentioning the DSML substring exits 0 silently"
else
    fail "loop_check prose-markup: rc=$PROSE_RC -- $(cat "$TMP/prose13.out")"
fi

if [ "$INLINE_RC" -eq 0 ] && [ ! -s "$TMP/inline13.out" ]; then
    pass "loop_check: markup token quoted mid-line in backticks exits 0 silently"
else
    fail "loop_check inline-markup: rc=$INLINE_RC -- $(cat "$TMP/inline13.out")"
fi

# --- 13c. Direct: loop_check.py's context ceiling (inc-xiqb) --------------
# Runs everywhere, sandbox or not. The context-over fixture carries one step
# whose context (input + cache.read + cache.write) is 100001 with no loop text:
# the default ceiling 100000 must flag it. A copy at exactly 100000 must stay
# green, and INCURSION_DS_CONTEXT_CEILING=50000 must lower the ceiling so a
# step at 60000 fires.
CONTEXT_OV_FIXTURE="$ROOT/tools/opencode/fixtures/context-over.jsonl"
python3 - "$TMP/context-exact.jsonl" "$TMP/context-env.jsonl" <<'PY'
import json, sys

exact, env = sys.argv[1], sys.argv[2]


def write(path, mid, context_input, cache_read, cache_write):
    with open(path, "w") as fh:
        fh.write(json.dumps({"type": "step_start", "part": {"messageID": mid}}) + "\n")
        fh.write(json.dumps({"type": "text",
                             "part": {"messageID": mid, "text": "ordinary reply.\n"}}) + "\n")
        fh.write(json.dumps({"type": "step_finish",
                             "part": {"messageID": mid, "tokens": {
                                 "input": context_input, "output": 5,
                                 "cache": {"read": cache_read, "write": cache_write}}}}) + "\n")


# Exactly 100000: 1001 + 50000 + 48999.
write(exact, "msg_ctxexact", 1001, 50000, 48999)
# 60000: over the lowered ceiling, under the default.
write(env, "msg_ctxenv", 1, 50000, 9999)
PY

CTX_OVER_RC=0; CTX_EXACT_RC=0; CTX_ENV_RC=0
python3 "$ROOT/tools/opencode/loop_check.py" "$CONTEXT_OV_FIXTURE" > "$TMP/ctxover13.out" 2>&1
CTX_OVER_RC=$?
python3 "$ROOT/tools/opencode/loop_check.py" "$TMP/context-exact.jsonl" > "$TMP/ctxexact13.out" 2>&1
CTX_EXACT_RC=$?
INCURSION_DS_CONTEXT_CEILING=50000 python3 "$ROOT/tools/opencode/loop_check.py" "$TMP/context-env.jsonl" > "$TMP/ctxenv13.out" 2>&1
CTX_ENV_RC=$?

if [ "$CTX_OVER_RC" -eq 1 ] && grep -q '^context ' "$TMP/ctxover13.out" \
    && grep -q 'context_tokens=100001' "$TMP/ctxover13.out" \
    && ! grep -q '^loop \|^markup ' "$TMP/ctxover13.out"; then
    pass "loop_check (F4): context 100001 exits 1 with a context line and no text tail"
else
    fail "loop_check (F4): rc=$CTX_OVER_RC -- $(cat "$TMP/ctxover13.out")"
fi

if [ "$CTX_EXACT_RC" -eq 0 ] && [ ! -s "$TMP/ctxexact13.out" ]; then
    pass "loop_check (F4): context exactly 100000 exits 0 silently"
else
    fail "loop_check (F4 exact): rc=$CTX_EXACT_RC -- $(cat "$TMP/ctxexact13.out")"
fi

if [ "$CTX_ENV_RC" -eq 1 ] && grep -q '^context ' "$TMP/ctxenv13.out" \
    && grep -q 'ceiling=50000' "$TMP/ctxenv13.out"; then
    pass "loop_check (F4 env): INCURSION_DS_CONTEXT_CEILING=50000 flags context 60000"
else
    fail "loop_check (F4 env): rc=$CTX_ENV_RC -- $(cat "$TMP/ctxenv13.out")"
fi

# --- 14. The proxy forwards a POST and records it byte-identically --------
# Runs everywhere: the proxy and the fake upstream both bind 127.0.0.1 and
# never touch the network. A body with a distinctive byte pattern proves the
# request file is the exact bytes sent, not a re-serialisation.
REC14="$TMP/rec14"; mkdir -p "$REC14"
start_upstream plain 0
UP14="$FU_PORT"
REQ_BODY='{"model":"deepseek-ai/DeepSeek-V4.1-Flash","stream":true,"messages":[{"role":"user","content":"hello \u00e9\u00ff"}]}'
if [ -z "$UP14" ]; then
    fail "proxy forward: fake upstream did not start"
else
    export INCURSION_DS_UPSTREAM="http://127.0.0.1:$UP14"
    start_proxy "$REC14"
    unset INCURSION_DS_UPSTREAM
    PX14="$PROXY_PORT"
    if [ -z "$PX14" ]; then
        fail "proxy forward: proxy did not start: $(cat "$TMP/proxy.log")"
    else
        printf '%s' "$REQ_BODY" > "$TMP/req14.body"
        BODY_BYTES="$(wc -c < "$TMP/req14.body" | tr -d ' ')"
        curl -sS -m 10 -o "$TMP/resp14" -w '%{http_code}' \
            -X POST "http://127.0.0.1:$PX14/v1/openai/chat/completions?beta=1" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer SENTINEL-KEY-123" \
            --data-binary @"$TMP/req14.body" > "$TMP/code14" 2>"$TMP/curl14.err"
        HTTP14="$(cat "$TMP/code14")"
        stop_proxy_direct
        if [ "$HTTP14" = "200" ] \
            && cmp -s "$REC14/0001.request.json" "$TMP/req14.body" \
            && grep -q '"up"' "$REC14/0001.response.txt" \
            && [ -s "$REC14/0001.meta.json" ] \
            && grep -q '"status": 200' "$REC14/0001.meta.json" \
            && grep -q '"path": "/v1/openai/chat/completions?beta=1"' "$REC14/0001.meta.json" \
            && grep -q "\"request_bytes\": $BODY_BYTES" "$REC14/0001.meta.json"; then
            pass "proxy forwards a POST and records request byte-identically, plus response and meta"
        else
            fail "proxy forward: http=$HTTP14 req-bytes=$(wc -c < "$REC14/0001.request.json" 2>/dev/null)/$BODY_BYTES meta=$(cat "$REC14/0001.meta.json" 2>/dev/null) -- $(cat "$TMP/curl14.err")"
        fi
    fi
fi
FU_HITS14="${FU_HITS:-}"
stop_upstream

# --- 15. Streaming reaches the client before upstream finishes ------------
# The fake upstream holds the second chunk for FU_SLEEP seconds. A raw client
# must read the first chunk well before the second; a proxy that buffered the
# whole body would deliver both at once.
REC15="$TMP/rec15"; mkdir -p "$REC15"
start_upstream stream 2
UP15="$FU_PORT"
if [ -z "$UP15" ]; then
    fail "streaming: fake upstream did not start"
else
    export INCURSION_DS_UPSTREAM="http://127.0.0.1:$UP15"
    start_proxy "$REC15"
    unset INCURSION_DS_UPSTREAM
    PX15="$PROXY_PORT"
    if [ -z "$PX15" ]; then
        fail "streaming: proxy did not start: $(cat "$TMP/proxy.log")"
    else
        STREAM_OUT="$(python3 - "$PX15" <<'PY'
import socket, sys, time
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])))
s.sendall(b"POST /v1/openai/chat/completions HTTP/1.1\r\nHost: x\r\n"
          b"Content-Length: 2\r\n\r\n{}")
t0 = time.time(); s.settimeout(6.0)
buf = b""; first = second = None
while True:
    try:
        data = s.recv(65536)
    except socket.timeout:
        break
    if not data:
        break
    buf += data
    if first is None and b"data: first" in buf:
        first = time.time() - t0
    if second is None and b"data: second" in buf:
        second = time.time() - t0
        break
s.close()
ok = first is not None and (second is None or first < second - 1.0)
print("OK" if ok else "BAD first=%s second=%s" % (first, second))
PY
)"
        stop_proxy_direct
        if [ "$STREAM_OUT" = "OK" ]; then
            pass "streaming: the first chunk reaches the client before the second is sent"
        else
            fail "streaming: $STREAM_OUT"
        fi
    fi
fi
stop_upstream

# --- 16. The Authorization header is relayed, never recorded --------------
# The upstream MUST see the header (relay works); no file under the record dir
# may contain the sentinel (nothing records headers). Assertion 14 sent it.
LEAK16=0
if [ -d "$REC14" ]; then
    grep -rqF "SENTINEL-KEY-123" "$REC14" && LEAK16=1
fi
grep -qF "SENTINEL-KEY-123" "$TMP/proxy.log" 2>/dev/null && LEAK16=1
UPSTREAM_SAW=0
if [ -n "${FU_HITS14:-}" ] && [ -f "$FU_HITS14" ] \
    && grep -qF "AUTH Bearer SENTINEL-KEY-123" "$FU_HITS14"; then
    UPSTREAM_SAW=1
fi
if [ "$LEAK16" -eq 0 ] && [ "$UPSTREAM_SAW" -eq 1 ]; then
    pass "Authorization relayed to upstream; the sentinel key is in no file under the record dir"
else
    fail "auth header: leak=$LEAK16 upstream-saw=$UPSTREAM_SAW"
fi

# --- 17. Wrapper e2e: one HTTP POST to the proxy, one recorded request ----
# The fake opencode makes a real POST to $INCURSION_DS_BASEURL (the wrapper's
# proxy) and emits success events. The run dir must hold exactly one recorded
# request, and the proxy the wrapper recorded in proxy.pid must be gone.
start_upstream plain 0
UP17="$FU_PORT"
if [ -z "$UP17" ]; then
    skip "wrapper proxy e2e: fake upstream did not start"
else
    FAKEHOME="$TMP/home17"; mkdir -p "$FAKEHOME"
    WORK="$TMP/wt17"; mkdir -p "$WORK"
    BRIEF="$TMP/brief17.txt"; echo "do a thing" > "$BRIEF"
    LEDGER="$TMP/ledger17.jsonl"; : > "$LEDGER"
    : > "$TMP/rec.17"
    RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.17" \
        INCURSION_FAKE_MODE=success INCURSION_FAKE_POST=1 INCURSION_FAKE_HTTP_OUT="$TMP/http17.out" \
        INCURSION_DS_UPSTREAM="http://127.0.0.1:$UP17" \
        INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
        "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.17" 2> "$TMP/err.17"; echo $?)"
    stop_upstream
    RUNDIR17_RAW="$(ls -d "$WORK"/logs/opencode/* 2>/dev/null | head -n 1)"
    RECORDED17=""
    PROXY_PID17=""
    if [ -n "$RUNDIR17_RAW" ]; then
        RUNDIR17="$(cd "$RUNDIR17_RAW" && pwd -P)"
        RECORDED17="$(ls "$RUNDIR17/requests"/*.request.json 2>/dev/null)"
        [ -f "$RUNDIR17/proxy.pid" ] && PROXY_PID17="$(cat "$RUNDIR17/proxy.pid")"
    fi
    REQ_COUNT17=0
    if [ -n "$RECORDED17" ]; then
        REQ_COUNT17="$(printf '%s\n' $RECORDED17 | grep -c .)"
    fi
    PROXY_ALIVE17=0
    if [ -n "$PROXY_PID17" ] && kill -0 "$PROXY_PID17" 2>/dev/null; then
        PROXY_ALIVE17=1
    fi
    if [ "$SANDBOX_OK" -eq 0 ]; then
        skip "wrapper proxy e2e: not run (sandbox-exec cannot nest here)"
    elif [ "$REQ_COUNT17" -eq 1 ] && grep -q 'STATUS 200' "$TMP/http17.out" \
        && [ -n "$PROXY_PID17" ] && [ "$PROXY_ALIVE17" -eq 0 ]; then
        pass "wrapper e2e: one recorded request in the run dir, proxy dead after exit"
    else
        fail "wrapper e2e: rc=$RC requests=$REQ_COUNT17 http=$(head -n 1 "$TMP/http17.out" 2>/dev/null) proxy-pid=$PROXY_PID17 alive=$PROXY_ALIVE17 -- $(cat "$TMP/err.17")"
    fi
fi

# --- 18. Loop kill copies the run dir, including requests/, aside ---------
# A loop kill must preserve the recorded model calls with the events. The fake
# POSTs once (so requests/ is non-empty) and then emits the loop fixture, so
# the canary fires. The redirected runs dir must hold a directory containing
# events.jsonl AND requests/0001.request.json, and must NOT contain the
# excluded data/ or state/ subdirs.
start_upstream plain 0
UP18="$FU_PORT"
if [ -z "$UP18" ]; then
    skip "loop-dir copy: fake upstream did not start"
else
    FAKEHOME="$TMP/home18"; mkdir -p "$FAKEHOME"
    WORK="$TMP/wt18"; mkdir -p "$WORK"
    BRIEF="$TMP/brief18.txt"; echo "do a thing" > "$BRIEF"
    LEDGER="$TMP/ledger18.jsonl"; : > "$LEDGER"
    RUNS18="$TMP/runs18"; mkdir -p "$RUNS18"
    : > "$TMP/rec.18"
    # The loop fixture passes 100K context before its loop step, so raise the ceiling to isolate the loop rule.
    RC="$(HOME="$FAKEHOME" INCURSION_OPENCODE_BIN="$FAKE" INCURSION_FAKE_REC="$TMP/rec.18" \
        INCURSION_FAKE_MODE=loop INCURSION_FAKE_EVENTS="$LOOP_FIXTURE" \
        INCURSION_DS_CONTEXT_CEILING=1000000000000 \
        INCURSION_FAKE_POST=1 INCURSION_FAKE_HTTP_OUT="$TMP/http18.out" \
        INCURSION_DS_UPSTREAM="http://127.0.0.1:$UP18" \
        INCURSION_DEEPSEEK_KEY=canary-x INCURSION_DEEPSEEK_LEDGER="$LEDGER" \
        INCURSION_OPENCODE_RUNS_DIR="$RUNS18" \
        INCURSION_WATCHDOG_STARTUP=5 INCURSION_WATCHDOG_IDLE=30 INCURSION_WATCHDOG_POLL=1 \
        INCURSION_WATCHDOG_GRACE=2 \
        "$WRAPPER" "$WORK" "$BRIEF" > "$TMP/out.18" 2> "$TMP/err.18"; echo $?)"
    stop_upstream
    COPYDIR18="$(ls -d "$RUNS18"/*/ 2>/dev/null | head -n 1)"
    if [ "$SANDBOX_OK" -eq 0 ]; then
        skip "loop-dir copy: not run (sandbox-exec cannot nest here)"
    elif [ "$RC" -eq 3 ] && [ -n "$COPYDIR18" ] \
        && [ -f "$COPYDIR18/events.jsonl" ] \
        && [ -f "$COPYDIR18/requests/0001.request.json" ] \
        && [ ! -d "$COPYDIR18/data" ] && [ ! -d "$COPYDIR18/state" ]; then
        pass "loop kill copies the run dir including requests/, excluding data/ and state/"
    else
        fail "loop-dir copy: rc=$RC dir=$COPYDIR18 contents=$(ls -A "$COPYDIR18" 2>/dev/null | tr '\n' ' ') -- $(cat "$TMP/err.18")"
    fi
fi

if [ "$FAIL" -eq 0 ] && [ "$SKIP_COUNT" -eq 0 ]; then
    echo "PASS: check_opencode_ds.sh, all assertions"
    exit 0
elif [ "$FAIL" -eq 0 ]; then
    echo "PASS (partial): check_opencode_ds.sh, $SKIP_COUNT assertion(s) skipped and not counted;"
    echo "                rerun outside any sandbox to run all (exit 2 = incomplete)"
    exit 2
else
    echo "FAIL: check_opencode_ds.sh, at least one assertion failed above"
    exit 1
fi
