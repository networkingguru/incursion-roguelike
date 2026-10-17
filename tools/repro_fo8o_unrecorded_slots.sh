#!/bin/bash
# gate: none it compiles sandbox modules (~1 minute) and needs a build, so the
# gate must not run it on every branch; tools/check_resource_order.sh is the
# gate. The write-up is next to its sibling in tools/README.md.
#
# inc-fo8o. The reproduction for the ledger-records-the-module rule. The order
# guard (inc-4320) fires only when a move BREAKS the order, so a legal append
# still leaves tools/resource_order.ledger lagging the module: a later merge can
# move the appended slot with every existing check green. This shows the new
# pieces catch it, judged by tools/resource_order_check.py and
# tools/order_guard.sh against a COPY of the ledger (never the committed one):
#
#   (a) append one Effect at the end of the last-compiled lib file
#         plain check                         -> exit 0
#         --require-recorded                  -> exit 1 (the ledger lags)
#   (b) --record against a COPY of the ledger
#         --require-recorded --ledger <copy>  -> exit 0 (now recorded)
#   (c) insert a SECOND Effect ahead of the first new one
#         plain check --ledger <copy>         -> exit 1 (the first new slot moved)
#   (d) tools/order_guard.sh --ledger <copy> -> exit 1 (the landing check)
#
# Case (c) is the one that broke Semirath's flute on the inc-pu6v epic: a plain
# append looked legal, and a later bead inserted ahead of it. Each sandbox is a
# copy of lib/ with one edit, compiled by ./incursion-headless -compile (the
# technique of tools/check_resource_order_mutations.sh).
#
# Specimens (compiled module, compile logs, check output) stay under
# logs/fo8o-unrecorded-slots/.  Usage: tools/repro_fo8o_unrecorded_slots.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN=./incursion-headless
COMPILER=./incursion-headless
LEDGER=tools/resource_order.ledger
WORK="$ROOT/logs/fo8o-unrecorded-slots"

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -x "$COMPILER" ] || {
    echo "INCONCLUSIVE: $COMPILER is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$LEDGER" ] || {
    echo "FAIL: no ledger at $LEDGER. Run: tools/check_resource_order.sh --record"
    exit 1
}

rm -rf "$WORK"
mkdir -p "$WORK"
echo "Specimens: $WORK"

FAILED=0
pass() { echo "  PASS $1"; }
fail() { echo "  FAIL $1"; FAILED=1; }

# expect_rc <label> <want> <got>
expect_rc() { # label want got
    if [ "$3" = "$2" ]; then
        pass "$1 (exit $3)"
    else
        fail "$1: exit $3, wanted $2"
    fi
}

new_sandbox() { # name -> echoes the sandbox root
    local name="$1"
    local sb="$WORK/$name"
    mkdir -p "$sb/mod" "$sb/logs"
    cp -Rf "$ROOT/lib" "$sb/lib"
    ln -sfn "$ROOT/inc" "$sb/inc"
    echo "$sb"
}

compile_sandbox() { # sandbox
    local sb="$1"
    INCURSIONPATH="$sb/" "$COMPILER" -compile main.irc \
        < /dev/null > "$sb/compile.log" 2>&1
    local status=$?
    if [ "$status" -ne 0 ] || [ ! -f "$sb/mod/Incursion.Mod" ]; then
        tail -20 "$sb/compile.log"
        fail "the $(basename "$sb") sandbox module did not compile (exit $status)"
        exit 1
    fi
}

# --- the edits -------------------------------------------------------------

# (a) append one Effect at the very end of lib/main.irc, the last-compiled file.
append_first() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/main.irc"
t = p.read_text()
t += ('\n0 Effect "Fo8o Oracle First Append" : EA_GENERIC\n'
      '  { }\n')
p.write_text(t)
PY
}

# (c) insert a second Effect BEFORE the first new one, so the first new slot
# moves. Reuses the name (a) appended so the ordering is unambiguous.
insert_ahead() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/main.irc"
t = p.read_text()
old = '\n0 Effect "Fo8o Oracle First Append" : EA_GENERIC\n  { }\n'
assert old in t, "the first append is not present"
new = ('\n0 Effect "Fo8o Oracle Insert Ahead" : EA_GENERIC\n'
       '  { }\n' + old)
p.write_text(t.replace(old, new, 1))
PY
}

# --- the cases -------------------------------------------------------------

sb="$(new_sandbox "append-then-insert")"
copy="$sb/ledger.copy"
cp -f "$LEDGER" "$copy"

# (a) append one Effect at the end of the last-compiled lib file.
echo "(a) append one Effect at the end of lib/main.irc:"
append_first "$sb" || fail "the append edit did not apply"
compile_sandbox "$sb"

python3 tools/resource_order_check.py --module-root "$sb" > "$sb/plain.log" 2>&1
expect_rc "plain check sees a legal append" 0 $?

python3 tools/resource_order_check.py --require-recorded \
    --module-root "$sb" --ledger "$copy" > "$sb/require.log" 2>&1
expect_rc "--require-recorded sees the ledger lag the module" 1 $?

# (b) --record against a COPY of the ledger, never the committed one.
echo "(b) --record against a copy of the ledger:"
python3 tools/resource_order_check.py --record \
    --module-root "$sb" --ledger "$copy" > "$sb/record.log" 2>&1
expect_rc "--record accepts the legal append" 0 $?
cmp -s "$LEDGER" "$copy" && fail "--record changed nothing (the committed ledger may equal the copy)"
grep -qF "Fo8o Oracle First Append" "$copy" || fail "--record wrote no appended Effect"

python3 tools/resource_order_check.py --require-recorded \
    --module-root "$sb" --ledger "$copy" > "$sb/require2.log" 2>&1
expect_rc "--require-recorded passes against the recorded copy" 0 $?

# (c) now insert a second Effect ahead of the first new one: the copy records
# the first new slot at its end, so the plain check against the copy must fail.
echo "(c) insert a second Effect ahead of the first new one:"
insert_ahead "$sb" || fail "the insert-ahead edit did not apply"
compile_sandbox "$sb"

python3 tools/resource_order_check.py --module-root "$sb" \
    --ledger "$copy" > "$sb/plain-moved.log" 2>&1
expect_rc "plain check --ledger copy sees the first new slot move" 1 $?

# (d) tools/order_guard.sh --ledger <copy>: the landing check must fail too.
echo "(d) tools/order_guard.sh --ledger <copy>:"
INCURSION_ORDER_BIN="$ROOT/$BIN" tools/order_guard.sh \
    --module-root "$sb" --ledger "$copy" > "$sb/guard.log" 2>&1
expect_rc "order guard --ledger copy sees the moved slot" 1 $?

echo
if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: see above. Every specimen is under $WORK"
    exit 1
fi
echo "PASS: an unrecorded append passes the plain check but not --require-recorded;"
echo "      --record against a ledger copy records it; a later insert ahead of the"
echo "      new slot then fails both the plain check and the landing guard."
echo "      Specimens: $WORK"
