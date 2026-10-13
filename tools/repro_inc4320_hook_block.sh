#!/bin/sh
# gate: none it compiles two sandbox modules (~15 seconds) against a built
# ./incursion-headless, so the gate must not run it on every branch;
# .beads/hooks/pre-commit is the subject.
#
# inc-4320 phase 4. Reproduces the commit-hook block at the end of
# .beads/hooks/pre-commit. The harness is built from TRACKED files on every run:
# a fake bin/git (below) answers only the read-only git queries the hook and
# tools/order_guard.sh make, and two sandbox module roots are compiled from a
# copy of lib/ the way tools/repro_inc4320_order_guard.sh does. Nothing here
# depends on logs/ from an earlier run, so the reproduction runs on a fresh
# checkout. It proves that a commit with no staged lib/ file falls out of the
# block, merge commits are skipped, a stale module is refused, a fresh good
# module reaches the order guard and passes, a moved variable is refused, and a
# no-lib commit reaches a line appended after the block.
#
# Every artifact lives under logs/inc-4320-hook-repro/. Nothing here writes
# outside that directory (the order check only READS the approver's fixed path;
# it never touches ~/.config).
#
# Usage: tools/repro_inc4320_hook_block.sh [hook-path]
#   hook-path defaults to .beads/hooks/pre-commit. Point it at a mutated copy
#   to watch a case go FAIL (e.g. a copy with the order-guard call removed).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

HOOK="${1:-.beads/hooks/pre-commit}"
BIN=./incursion-headless
COMPILER=./incursion-headless
WORK="$ROOT/logs/inc-4320-hook-repro"

if [ ! -x "$BIN" ]; then
    echo "INCONCLUSIVE: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
fi
if [ ! -f "$HOOK" ]; then
    echo "INCONCLUSIVE: no hook file at $HOOK"
    exit 2
fi
if [ ! -f "tools/resource_order.ledger" ]; then
    echo "FAIL: no ledger at tools/resource_order.ledger. Run: tools/check_resource_order.sh --record"
    exit 1
fi

# Delete and recreate our own directory, so a stale harness can never satisfy us.
rm -rf "$WORK"
mkdir -p "$WORK/bin"
echo "Specimens: $WORK"

# --- the fake git, written here so the repro needs nothing from an earlier run.
# It answers only the read-only queries the hook and tools/order_guard.sh make:
# FAKE_ROOT is the root the hook treats as the toplevel, FAKE_STAGED is the
# staged lib/ list, FAKE_MERGE=1 makes a merge commit, FAKE_BEAD names the branch.
cat > "$WORK/bin/git" <<'GIT'
#!/bin/sh
root="${FAKE_ROOT:?FAKE_ROOT unset}"
args="$*"
case "$args" in
  "rev-parse --git-path MERGE_HEAD")
    if [ "${FAKE_MERGE:-}" = "1" ]; then mkdir -p "$root/.gitdir"; : > "$root/.gitdir/MERGE_HEAD"; echo "$root/.gitdir/MERGE_HEAD"; else echo "$root/.gitdir/MERGE_HEAD.none"; fi ;;
  "rev-parse --git-path "*)
    echo "$root/.gitdir/$(printf '%s' "$args" | sed 's/.*--git-path //')" ;;
  "rev-parse --show-toplevel") echo "$root" ;;
  "rev-parse --absolute-git-dir") echo "$root/.gitdir" ;;
  "rev-parse --git-common-dir") echo "$root/.gitcommon" ;;
  "rev-parse --abbrev-ref HEAD") echo "${FAKE_BEAD:-inc-4320}" ;;
  "diff --cached --name-only -- lib/")
    for f in ${FAKE_STAGED:-}; do echo "$f"; done ;;
  "diff --cached --name-only"*)
    for f in ${FAKE_STAGED:-}; do echo "$f"; done ;;
  *) : ;;
esac
exit 0
GIT

# The beads block at the top of the hook would otherwise call whatever real bd
# is on PATH (and read the real .beads database). Neutralize it so the repro is
# self-contained and deterministic: a stub that succeeds quietly.
cat > "$WORK/bin/bd" <<'BD'
#!/bin/sh
exit 0
BD

chmod +x "$WORK/bin/git" "$WORK/bin/bd"
PATH="$WORK/bin:$PATH"
export PATH

FAILED=0

# --- sandbox builders, the technique of tools/repro_inc4320_order_guard.sh ----

new_sandbox() { # name -> echoes the sandbox root
    name="$1"
    sb="$WORK/$name"
    mkdir -p "$sb/mod" "$sb/logs" "$sb/tools"
    cp -Rf "$ROOT/lib" "$sb/lib"
    ln -sfn "$ROOT/inc" "$sb/inc"
    ln -sfn "$ROOT/incursion-headless" "$sb/incursion-headless"
    for f in order_guard.sh resource_order_check.py order_approval_path.sh resource_order.ledger; do
        cp -p "$ROOT/tools/$f" "$sb/tools/$f"
    done
    echo "$sb"
}

compile_sandbox() { # sandbox
    sb="$1"
    INCURSIONPATH="$sb/" "$COMPILER" -compile main.irc \
        < /dev/null > "$sb/compile.log" 2>&1
    status=$?
    if [ "$status" -ne 0 ] || [ ! -f "$sb/mod/Incursion.Mod" ]; then
        tail -20 "$sb/compile.log"
        echo "FAIL: the $(basename "$sb") sandbox module did not compile (exit $status)"
        exit 1
    fi
}

# Insert a variable before an existing one in the Entangle body
# (lib/pspells.irh). The declaration's ordinal shifts, so the body moved.
var_insert_before() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/pspells.irh"
t = p.read_text()
old = "bool cast_flag, found_flag;"
assert old in t
p.write_text(t.replace(old, "bool cast_flag, inserted_flag, found_flag;", 1))
PY
}

# Two module roots: a plain copy of lib/ (order-legal) and one with the moved
# variable (order-illegal). Build them once.
GOOD="$(new_sandbox good)"
compile_sandbox "$GOOD"
BAD="$(new_sandbox bad)"
var_insert_before "$BAD" || { echo "FAIL: the bad-sandbox edit did not apply"; exit 1; }
compile_sandbox "$BAD"

# Hook under test, copied so the real .beads/hooks/pre-commit is never edited.
cp "$HOOK" "$WORK/hook-copy"
# For case 6 only: a marker line appended AFTER the inc-4320 block, to prove a
# no-lib commit reaches code a later person appends there.
cp "$HOOK" "$WORK/hook-tail-copy"
printf '\n# APPENDED AFTER THE INC-4320 BLOCK, FOR THE TEST ONLY\necho "REACHED-AFTER-BLOCK"\n' >> "$WORK/hook-tail-copy"

# --- the case runner ---------------------------------------------------------

# run <hook> <root> <staged> <merge> <label> -> rc in $rc, output in $out
run() {
    hook="$1"; rroot="$2"; staged="$3"; merge="$4"; label="$5"
    out="$WORK/$label.out"
    FAKE_ROOT="$rroot" FAKE_STAGED="$staged" FAKE_MERGE="$merge" \
        sh "$hook" >"$out" 2>&1
    rc=$?
}

# expect <label> <want-rc> <want-substr> <forbid-substr>
# An empty want-substr means "no required text"; an empty forbid-substr means
# "nothing forbidden". Prints PASS or FAIL and records a failure.
expect() {
    label="$1"; want_rc="$2"; want_text="$3"; forbid_text="$4"
    if [ "$rc" != "$want_rc" ]; then
        echo "CASE $label: FAIL (exit $rc, wanted $want_rc)"
        sed 's/^/    | /' "$out"
        FAILED=1
        return
    fi
    if [ -n "$want_text" ] && ! grep -qF "$want_text" "$out"; then
        echo "CASE $label: FAIL (exit $rc ok, but message '$want_text' missing)"
        sed 's/^/    | /' "$out"
        FAILED=1
        return
    fi
    if [ -n "$forbid_text" ] && grep -qF "$forbid_text" "$out"; then
        echo "CASE $label: FAIL (exit $rc ok, but unexpected '$forbid_text')"
        sed 's/^/    | /' "$out"
        FAILED=1
        return
    fi
    echo "CASE $label: PASS (exit $rc)"
}

# Case 1: no staged lib/ file -> the block does nothing, hook succeeds.
run "$WORK/hook-copy" "$GOOD" "" "" "case1-nolib"
expect "case1-nolib" 0 "" "lib/ changed since the module was built"

# Case 2: merge commit -> the whole block is skipped.
run "$WORK/hook-copy" "$GOOD" "" "1" "case2-merge"
expect "case2-merge" 0 "" "lib/ changed since the module was built"

# Case 3: staged lib/ file newer than the module -> rebuild refusal.
touch "$GOOD/lib/classes.irh"
run "$WORK/hook-copy" "$GOOD" "lib/classes.irh" "" "case3-stale-module"
expect "case3-stale-module" 1 "lib/ changed since the module was built" ""

# Case 4: fresh good module, staged lib/ file older -> order guard passes.
touch "$GOOD/mod/Incursion.Mod"
run "$WORK/hook-copy" "$GOOD" "lib/classes.irh" "" "case4-order-ok"
expect "case4-order-ok" 0 "order check: ok" ""

# Case 5: fresh module that moved a variable -> order guard refusal.
touch "$BAD/mod/Incursion.Mod"
run "$WORK/hook-copy" "$BAD" "lib/classes.irh" "" "case5-order-fail"
expect "case5-order-fail" 1 "a variable was inserted, removed or swapped" ""

# Case 6: no staged lib/ file must reach a line appended after the block.
run "$WORK/hook-tail-copy" "$GOOD" "" "" "case6-after-block"
expect "case6-after-block" 0 "REACHED-AFTER-BLOCK" ""

echo
if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: see the CASE lines above. Every specimen is under $WORK"
    exit 1
fi
echo "PASS: all six cases held. Specimens: $WORK"
