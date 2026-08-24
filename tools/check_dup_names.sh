#!/bin/bash
# Check that the resource compiler rejects a same-case duplicate resource
# name (src/RComp.cpp, end of Game::CountResources; required by the v1 save
# schema's name table, docs/SAVE-SCHEMA-SPEC.md).
#
# How: build an INCURSIONPATH sandbox the way tools/dump_save.sh does, but
# with lib/ COPIED rather than symlinked (this check edits a script) and
# mod/ empty. Append a syntactically valid minimal Effect whose name
# duplicates "Heartstone" (lib/m_items.irh already declares one) to the
# COPY, compile, and demand BOTH a non-zero exit AND the rejection's own
# diagnostic -- the specific duplicate-name message naming the pool and the
# name, not merely any error that echoes the name (an ordinary syntax error
# would false-pass a looser grep). Then compile a clean sandbox copy and
# demand success. No tracked file is ever modified.
#
# Needs the graphical developer build: -compile lives behind DEBUG and this
# uses ./incursion, the binary ./build_macos.sh produces.
#
# Usage: tools/check_dup_names.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

BIN=./incursion
if [ ! -x "$BIN" ]; then
    fail "$BIN is not built. Run: ./build_macos.sh"
    exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-dupnames.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

make_sandbox() {
    # $1 = sandbox dir. lib/ copied (this check edits a script in it), mod/
    # and the rest empty. inc/ symlinked read-only: the script preprocessor
    # resolves #include "Defines.h" via its built-in ../inc search path
    # (src/cpp3.c:60, setincdirs).
    mkdir -p "$1/mod" "$1/save" "$1/logs"
    cp -R "$ROOT/lib" "$1/lib"
    ln -sfn "$ROOT/inc" "$1/inc"
}

DIAG='duplicate Effect name "Heartstone"'

# --- 1. the poisoned sandbox: a second same-case "Heartstone" Effect ------
make_sandbox "$WORK/poisoned"
# The shape of an existing minimal Effect (lib/m_items.irh:299), so the
# compile fails for the duplicate name and not for a syntax error.
cat >> "$WORK/poisoned/lib/m_items.irh" <<'EOF'

AI_STONE Effect "Heartstone" : EA_GRANT
  { xval: ADJUST; yval: A_WIS; pval: PLUS_1PER1;
    Flags: EF_NEEDS_PLUS, EF_NAMEONLY; SC_THE; Level: PLUS_2PER1;
    Desc: "A deliberately duplicated effect for tools/check_dup_names.sh.";
    Lists:
      * ITEM_COST ABIL_BOOST_COST(150); }
EOF

INCURSIONPATH="$WORK/poisoned/" "$BIN" -compile main.irc \
    < /dev/null > "$WORK/poisoned.out" 2>&1
STATUS=$?
if [ "$STATUS" -eq 0 ]; then
    fail "the compile of a module with a duplicate Effect name exited 0 -- the rejection is not firing"
fi
if ! grep -qF "$DIAG" "$WORK/poisoned.out"; then
    echo "--- last 15 lines of the poisoned compile ---"
    tail -15 "$WORK/poisoned.out"
    fail "the compile failed, but not with the duplicate-name diagnostic ($DIAG)"
fi
if [ -f "$WORK/poisoned/mod/Incursion.Mod" ]; then
    fail "a module was written despite the duplicate-name error"
fi

# --- 2. the clean sandbox: the same compile must still succeed ------------
make_sandbox "$WORK/clean"
INCURSIONPATH="$WORK/clean/" "$BIN" -compile main.irc \
    < /dev/null > "$WORK/clean.out" 2>&1
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    echo "--- last 15 lines of the clean compile ---"
    tail -15 "$WORK/clean.out"
    fail "the clean compile exited $STATUS; the rejection is misfiring on legitimate names"
fi
if grep -q "duplicate .* name" "$WORK/clean.out"; then
    grep "duplicate .* name" "$WORK/clean.out" | head -5
    fail "the clean compile reported duplicate names"
fi
if [ ! -f "$WORK/clean/mod/Incursion.Mod" ]; then
    fail "the clean compile produced no module"
fi

# --- 3. nothing tracked was modified --------------------------------------
if ! git -C "$ROOT" diff --quiet -- lib mod; then
    fail "tracked files under lib/ or mod/ changed during this check"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: a same-case duplicate Effect name fails the compile with the"
    echo "      specific diagnostic, and the real scripts still compile clean."
    exit 0
fi
exit 1
