#!/bin/bash
# gate: none — the reproduction for tools/check_resource_order.sh. It compiles
# eight sandbox modules and is ~2 minutes of work, so the gate must not run it
# on every branch; tools/check_resource_order.sh (gate: live) is the gate.
#
# docs/SAVE-SCHEMA-SPEC.md, test-plan case 26. The build-time order check must
# be RED, and --record must REFUSE, for each of the six changes the append-only
# rule forbids in lib/:
#
#   insert a variable before an existing one in a body
#   remove a variable
#   swap two variables in one body
#   insert an Effect in the middle of the Effect array
#   remove an Effect
#   swap two Effects
#
# and it must be GREEN, with --record ACCEPTING, for the two legal appends and
# the two legal in-place renames (docs/SAVE-SCHEMA-SPEC.md, case 26, amended
# 2026-09-26):
#
#   append a variable at the end of a body
#   append an Effect at the end of its array
#   rename a variable in place
#   rename an Effect in place
#
# The append and rename cases are the point of the build-time check: an append
# extends a list and a rename leaves every name but one at its position, so the
# check passes BEFORE the ledger is re-recorded. That lets the ledger lag a
# legal change by one commit. --record then takes the new ledger. A rename
# changes a name in place, so the ledger is NOT a prefix of the module and a
# prefix test would wrongly reject it; this is the case the amended rule fixes.
#
# Each sandbox is a copy of lib/ with one edit, compiled by
# ./incursion-headless -compile (the technique of check_spell_god_drift.sh).
# The check is run against the committed ledger with --module-root pointing at
# the sandbox, and --record against a COPY of the ledger, so the committed one
# can never be touched here.
#
# Specimens (compiled modules, compile logs, check output) stay under
# logs/resource-order-mutations/.  Usage: tools/check_resource_order_mutations.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN=./incursion-headless
COMPILER=./incursion-headless
LEDGER=tools/resource_order.ledger
WORK="$ROOT/logs/resource-order-mutations"

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

# run_check <sandbox> <logfile> -> prints the check output to stdout, leaves it
# in the log, and returns the check's exit code.
run_check() { # sandbox logfile
    local sb="$1" log="$2"
    python3 tools/resource_order_check.py --module-root "$sb" > "$log" 2>&1
    local rc=$?
    cat "$log"
    return $rc
}

# run_record <sandbox> <ledger-copy> <logfile> -> exit code of --record.
run_record() { # sandbox ledger-copy logfile
    local sb="$1" copy="$2" log="$3"
    cp -f "$LEDGER" "$copy"
    python3 tools/resource_order_check.py --record \
        --module-root "$sb" --ledger "$copy" > "$log" 2>&1
    return $?
}

# expect_refused <name> <edit-fn> <needle>
# Builds the sandbox, proves the check is red with `needle` in the output, and
# proves --record refuses and leaves the ledger copy byte-identical.
expect_refused() { # name edit-fn needle
    local name="$1" edit="$2" needle="$3"
    local sb; sb="$(new_sandbox "$name")"
    "$edit" "$sb" || { fail "$name: the sandbox edit did not apply"; return; }
    compile_sandbox "$sb"

    local out rc crc
    out="$(run_check "$sb" "$sb/check.log")"; crc=$?
    grep -qF "$needle" <<< "$out" || {
        fail "$name: the check did not name '$needle'"
        return
    }
    [ "$crc" = 1 ] || { fail "$name: the check exited $crc, wanted 1"; return; }

    local copy="$sb/ledger.copy"
    out="$(run_record "$sb" "$copy" "$sb/record.log")"; rc=$?
    [ "$rc" = 1 ] || { fail "$name: --record exited $rc, wanted 1 (refused)"; return; }
    cmp -s "$LEDGER" "$copy" || { fail "$name: --record changed the ledger copy"; return; }
    grep -qF "REFUSED" "$sb/record.log" || { fail "$name: --record did not say REFUSED"; return; }

    echo "  RED  check=$crc record=$rc: $needle"
}

# expect_accepted <name> <edit-fn> <needle> <label>
# Builds the sandbox, proves the check is GREEN (a legal append or an in-place
# rename), then proves --record ACCEPTS and writes the new ledger. `needle` is
# the name the change adds or introduces; `label` names the change kind in the
# one-line result.
expect_accepted() { # name edit-fn needle label
    local name="$1" edit="$2" needle="$3" label="$4"
    local sb; sb="$(new_sandbox "$name")"
    "$edit" "$sb" || { fail "$name: the sandbox edit did not apply"; return; }
    compile_sandbox "$sb"

    local out rc crc
    out="$(run_check "$sb" "$sb/check.log")"; crc=$?
    [ "$crc" = 0 ] || { fail "$name: the check exited $crc, wanted 0 (a legal $label)"; return; }
    grep -q "^PASS:" <<< "$out" || { fail "$name: the check did not say PASS"; return; }
    grep -qF "$needle" "$LEDGER" && { fail "$name: the committed ledger already has '$needle'"; return; }

    local copy="$sb/ledger.copy"
    out="$(run_record "$sb" "$copy" "$sb/record.log")"; rc=$?
    [ "$rc" = 0 ] || { fail "$name: --record exited $rc, wanted 0 (a legal $label)"; return; }
    grep -qF "RECORDED" "$sb/record.log" || { fail "$name: --record did not say RECORDED"; return; }
    grep -qF "$needle" "$copy" || { fail "$name: --record wrote no '$needle'"; return; }
    cmp -s "$LEDGER" "$copy" && { fail "$name: --record left the ledger unchanged"; return; }

    echo "  GREEN check=$crc record=$rc ($label): $needle"
}

# --- the edits, each on a fresh sandbox of lib/ ---------------------------

# Entangle: `bool cast_flag, found_flag;` (lib/pspells.irh).
entangle_insert() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/pspells.irh"
t = p.read_text()
old = "bool cast_flag, found_flag;"
assert old in t
p.write_text(t.replace(old, "bool cast_flag, inserted_flag, found_flag;", 1))
PY
}
entangle_remove() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/pspells.irh"
t = p.read_text()
t = t.replace("bool cast_flag, found_flag;", "bool cast_flag;", 1)
t = t.replace("{ cast_flag = 0; found_flag = 0; },", "{ cast_flag = 0; },", 1)
t = t.replace("        found_flag = 1;\n", "", 1)
t = t.replace("if (found_flag && !cast_flag)", "if (!cast_flag)", 1)
assert "found_flag" not in t, "found_flag still present"
p.write_text(t)
PY
}
entangle_swap() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/pspells.irh"
t = p.read_text()
old = "bool cast_flag, found_flag;"
assert old in t
p.write_text(t.replace(old, "bool found_flag, cast_flag;", 1))
PY
}
entangle_append() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/pspells.irh"
t = p.read_text()
old = "bool cast_flag, found_flag;"
assert old in t
p.write_text(t.replace(old, "bool cast_flag, found_flag, appended_flag;", 1))
PY
}
# Rename the variable in place: the declaration keeps its ordinal and every use
# follows. The ledger records `found_flag` at ordinal 1; the module lacks that
# name and holds `found_flag_renamed` at ordinal 1, so the amended rule passes
# it as a rename (docs/SAVE-SCHEMA-SPEC.md, case 26).
entangle_rename() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/pspells.irh"
t = p.read_text()
assert t.count("found_flag") >= 3, "expected the declaration and its uses"
p.write_text(t.replace("found_flag", "found_flag_renamed"))
PY
}

# Effect calls. "Aura of Valour" is Effect position 1; the insert lands there
# because it is the first Effect declaration in lib/classes.irh.
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
effect_remove() {
    python3 - "$1" <<'PY'
import pathlib, sys
# Remove the whole "Aura of Valour" resource, braces counted so a nested body
# goes as one resource and not by a brittle line range.
p = pathlib.Path(sys.argv[1]) / "lib/classes.irh"
lines = p.read_text().splitlines(keepends=True)
out, skip, depth, opened = [], False, 0, False
for line in lines:
    if not skip and line.startswith('0 Effect "Aura of Valour" : EA_GRANT'):
        skip, depth, opened = True, 0, False
        continue
    if skip:
        depth += line.count("{") - line.count("}")
        if "{" in line:
            opened = True
        if opened and depth == 0:
            skip = False
        continue
    out.append(line)
assert not skip
p.write_text("".join(out))
PY
}
effect_swap() {
    python3 - "$1" <<'PY'
import pathlib, sys
# Exchange the names of "No Mind" and "Crippling Strike". Only the two
# declaration lines change, so the module still compiles and the Effect array
# holds the same set of names at two swapped positions.
p = pathlib.Path(sys.argv[1]) / "lib/classes.irh"
t = p.read_text()
assert 'Effect "No Mind" : EA_GENERIC' in t
assert 'Effect "Crippling Strike" : EA_GENERIC' in t
t = t.replace('Effect "No Mind" : EA_GENERIC',
              'Effect "TEMP Swap Placeholder" : EA_GENERIC', 1)
t = t.replace('Effect "Crippling Strike" : EA_GENERIC',
              'Effect "No Mind" : EA_GENERIC', 1)
t = t.replace('Effect "TEMP Swap Placeholder" : EA_GENERIC',
              'Effect "Crippling Strike" : EA_GENERIC', 1)
p.write_text(t)
PY
}
effect_append() {
    python3 - "$1" <<'PY'
import pathlib, sys
# lib/main.irc is parsed last, and its trailing declarations carry the highest
# positions in every array (see the APPEND-ONLY note there). A new Effect after
# the last declaration is the end of the Effect array.
p = pathlib.Path(sys.argv[1]) / "lib/main.irc"
t = p.read_text()
t += ('\n0 Effect "Resource Order Oracle Append" : EA_GENERIC\n'
      '  { }\n')
p.write_text(t)
PY
}
# Rename the Effect in place: only the declaration line's name changes, so the
# Effect array holds a different name at the same position 1. The ledger
# records "Aura of Valour" there; the module lacks it, so the amended rule
# passes it as a rename.
effect_rename() {
    python3 - "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "lib/classes.irh"
t = p.read_text()
old = '0 Effect "Aura of Valour" : EA_GRANT'
assert old in t
new = '0 Effect "Aura of Valour Renamed" : EA_GRANT'
p.write_text(t.replace(old, new, 1))
PY
}

# --- run them --------------------------------------------------------------

echo
echo "Illegal changes -- each must be RED, and --record must REFUSE:"
expect_refused "insert-var"  entangle_insert \
    "owner Entangle (array 3, position 807)"
expect_refused "remove-var"  entangle_remove \
    "owner Entangle (array 3, position 807)"
expect_refused "swap-var"    entangle_swap \
    "owner Entangle (array 3, position 807)"
expect_refused "insert-effect" effect_insert \
    "array 3 (Effect) in module slot 0"
expect_refused "remove-effect" effect_remove \
    "array 3 (Effect) in module slot 0"
expect_refused "swap-effect"  effect_swap \
    "array 3 (Effect) in module slot 0"

echo
echo "Legal appends -- each must be GREEN before --record, and --record must ACCEPT:"
expect_accepted "append-var"    entangle_append "appended_flag" "append"
expect_accepted "append-effect" effect_append   "Resource Order Oracle Append" "append"

echo
echo "Legal renames in place -- each must be GREEN, and --record must ACCEPT:"
expect_accepted "rename-var"    entangle_rename "found_flag_renamed" "rename"
expect_accepted "rename-effect" effect_rename   "Aura of Valour Renamed" "rename"

echo
if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: see above. Every specimen is under $WORK"
    exit 1
fi
echo "PASS: the six illegal changes are red and refused by --record; the two"
echo "      legal appends and two legal in-place renames are green and accepted"
echo "      by --record."
echo "      Specimens: $WORK"
