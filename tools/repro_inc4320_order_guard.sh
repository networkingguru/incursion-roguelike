#!/bin/bash
# gate: none it compiles three sandbox modules (~1 minute) and needs a build, so
# the gate must not run it on every branch; tools/order_guard.sh is the subject.
#
# inc-4320. The reproduction for the build-time order guard's refusal path. The
# guard's job is to fail closed when a resource or script variable moved, unless
# Brian approves the exact failure list for the bead. This exercises the refusal
# against sandbox modules, judged by tools/order_guard.sh --module-root:
#
#   insert a variable before an existing one in a body  -> exit 1, names the body
#   insert an Effect in the middle of the Effect array  -> exit 1, names the slot
#   append a new variable at the end of a body          -> exit 0
#
# The two illegal cases are the point: the guard must be RED and say which body
# or slot moved. The legal append is the control that proves the guard is not
# simply refusing everything. Each sandbox is a copy of lib/ with one edit,
# compiled by ./incursion-headless -compile (the technique of
# tools/check_resource_order_mutations.sh). Nothing here writes outside logs/
# and nothing touches the committed ledger or ~/.config.
#
# Usage: tools/repro_inc4320_order_guard.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN=./incursion-headless
COMPILER=./incursion-headless
LEDGER=tools/resource_order.ledger
WORK="$ROOT/logs/inc-4320-repro"

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"
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
fail() { echo "FAIL: $1"; FAILED=1; }

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

# guard <sandbox> <logfile> -> runs the guard against the sandbox and returns
# its exit code; the output is in the log.
guard() { # sandbox logfile
    local sb="$1" log="$2"
    tools/order_guard.sh --module-root "$sb" > "$log" 2>&1
    return $?
}

# expect_refused <name> <edit-fn> <needle>
expect_refused() { # name edit-fn needle
    local name="$1" edit="$2" needle="$3"
    local sb; sb="$(new_sandbox "$name")"
    "$edit" "$sb" || { fail "$name: the sandbox edit did not apply"; return; }
    compile_sandbox "$sb"

    guard "$sb" "$sb/guard.log"
    local rc=$?
    [ "$rc" = 1 ] || { fail "$name: the guard exited $rc, wanted 1"; return; }
    grep -qF "$needle" "$sb/guard.log" || {
        fail "$name: the guard did not name '$needle'"
        return
    }
    echo "  PASS: refused (exit $rc), named '$needle'"
}

# expect_allowed <name> <edit-fn>
expect_allowed() { # name edit-fn
    local name="$1" edit="$2"
    local sb; sb="$(new_sandbox "$name")"
    "$edit" "$sb" || { fail "$name: the sandbox edit did not apply"; return; }
    compile_sandbox "$sb"

    guard "$sb" "$sb/guard.log"
    local rc=$?
    [ "$rc" = 0 ] || { fail "$name: the guard exited $rc, wanted 0"; return; }
    echo "  PASS: allowed (exit $rc)"
}

# --- the edits, each on a fresh sandbox of lib/ ---------------------------

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

# Append a new variable at the END of the same body. The existing ordinals do
# not move, so the body is still a prefix of the ledger's and the guard passes.
var_append() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/pspells.irh"
t = p.read_text()
old = "bool cast_flag, found_flag;"
assert old in t
p.write_text(t.replace(old, "bool cast_flag, found_flag, appended_flag;", 1))
PY
}

# Insert an Effect at the head of the Effect array, before "Aura of Valour"
# (module slot 0). Every later Effect shifts.
effect_insert() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/classes.irh"
t = p.read_text()
old = '0 Effect "Aura of Valour" : EA_GRANT'
assert old in t
new = ('0 Effect "Resource Order Oracle Insert" : EA_GENERIC\n'
       '  { }\n\n' + old)
p.write_text(t.replace(old, new, 1))
PY
}

# --- run them --------------------------------------------------------------

echo
expect_refused "insert-var"    var_insert_before "Entangle"
expect_refused "insert-effect" effect_insert     "Aura of Valour"
expect_allowed "append-var"    var_append

echo
if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: see above. Every specimen is under $WORK"
    exit 1
fi
echo "PASS: the guard refused the inserted variable (naming Entangle) and the"
echo "      inserted Effect (naming Aura of Valour), and allowed the append."
echo "      Specimens: $WORK"
