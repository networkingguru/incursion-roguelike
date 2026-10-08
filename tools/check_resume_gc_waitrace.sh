#!/usr/bin/env bash
# gate: cheap
# gate-serial: reruns check_resume_gc.sh with a wall-clock wait_detached; CPU load could flip it
# Red proof for inc-2gl7: with the detached run's second forget delayed past a
# single 0.1 s poll, the old wait_detached returns after one key and b1 fails;
# the fixed wait_detached (wait for the expected count) still passes.
#
#   tools/check_resume_gc_waitrace.sh
#
# It runs the real check twice in a temp copy whose stub adds a one-time delay
# before the second forget (INCURSION_WAITRACE_DELAY), first restoring the old
# wait loop and then using the shipped one. Nothing in the repo is modified.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tools/check_resume_gc.sh"
TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

# Inject a delay into the stub's forget branch, armed only on the 2nd call.
# The stub is written by an unquoted heredoc in write_stub, so every $ that
# belongs to the stub must be escaped here (\$) to survive to the stub file.
python3 - "$SRC" "$TMP/check.sh" "$ROOT" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
anchor = 'if [ "\\$cmd" = "forget" ]; then\n'
inject = anchor + (
    '    nf="$TMP/forgetcount"\n'
    '    c=0; [ -f "\\$nf" ] && c="\\$(cat "\\$nf")"\n'
    '    c=\\$((c+1)); printf \'%s\' "\\$c" > "\\$nf"\n'
    '    [ "\\$c" -ge 2 ] && sleep "\\${INCURSION_WAITRACE_DELAY:-0.35}"\n'
)
assert s.count(anchor) == 1, "stub forget anchor not found"
s = s.replace(anchor, inject)
# The copy lives outside tools/, so pin ROOT at the real worktree.
s = s.replace(
    'ROOT="$(cd "$(dirname "$0")/.." && pwd)"',
    'ROOT="REALROOT"',
)
open(dst, "w").write(s.replace("REALROOT", sys.argv[3]))
PY
chmod +x "$TMP/check.sh"

# Build the old-loop variant by swapping the shipped wait_detached back. Anchor
# on the function itself, with any comment block directly above it, not on a
# comment's wording (which drifts).
python3 - "$TMP/check.sh" "$TMP/check_old.sh" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
old = '''# Wait for the detached --run to stop changing the store, up to ~5s.
wait_detached() {
    local i prev cur
    prev="$(forgot_keys)"
    for i in $(seq 1 50); do
        sleep 0.1
        cur="$(forgot_keys)"
        if [ "$cur" = "$prev" ] && [ -n "$cur" ]; then
            return 0
        fi
        prev="$cur"
    done
    return 0
}'''
# (?:#[^\n]*\n)* matches the leading comment block, then the function body
# runs from `wait_detached() {` to the first `}` at column 0.
pat = re.compile(r"(?:#[^\n]*\n)*wait_detached\(\) \{.*?\n\}", re.S)
if not pat.search(src):
    sys.stderr.write("waitrace: shipped wait_detached not found in the check copy\n")
    sys.exit(2)
src = pat.sub(old, src, count=1)
src = src.replace("wait_detached 2", "wait_detached")
open(sys.argv[2], "w").write(src)
PY
if [ $? -ne 0 ] || [ ! -f "$TMP/check_old.sh" ]; then
    echo "waitrace: could not build the old-loop variant" >&2
    exit 2
fi
chmod +x "$TMP/check_old.sh"

run() { # run <script> <label> <want: red|green>
    local out rc
    out="$(INCURSION_WAITRACE_DELAY="${INCURSION_WAITRACE_DELAY:-1.0}" bash "$1" 2>&1)"
    rc=$?
    echo "--- $2 ---"
    echo "$out" | grep -E '^(OK    b1|FAIL  b1|GREEN|RED)' || true
    if [ "$3" = "red" ]; then
        # Red for the right reason: b1 must be the failing assertion.
        grep -q '^FAIL  b1' <<<"$out" && [ "$rc" -ne 0 ]
    else
        # Green: b1 passes and the suite exits 0.
        grep -q '^OK    b1' <<<"$out" && [ "$rc" -eq 0 ]
    fi
}

st=0
run "$TMP/check_old.sh" "old wait loop (expect b1 FAIL / RED)" red || st=1
run "$TMP/check.sh" "fixed wait loop (expect b1 OK / GREEN)" green || st=1
[ "$st" -eq 0 ] && echo "waitrace: old red, fixed green -- as intended"
exit "$st"
