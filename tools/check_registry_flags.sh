#!/bin/bash
# gate: live
# Do the heap-built save-format test registries start with zeroed mode flags?
# (bd inc-38d5)
#
# THE DEFECT. Registry::Registry() initialises ObjTable, DataTable,
# LastUsedHandle and reg_log, but never saveMode or loadMode (inc/Base.h). The
# game's own registries are globals, so the C++ zero-initialisation of static
# storage gives them false as a side effect and the omission is invisible.
# The save-format test harnesses build registries with `new Registry()` on the
# heap instead -- V1RunSchemaLoad (src/SaveV1.cpp) and the six in
# V1RunSchemaTest -- and a heap registry starts with whatever bytes were in
# the allocation.
#
# WHY THAT MATTERS. When loadMode is non-zero, every constructor that asks
# `theRegistry->Loading()` takes the load-time branch and skips setup:
#   - Array::Array() (src/Base.cpp) leaves Items random, and the destructor's
#     `if (Items) free(Items)` then frees a stray pointer (SIGTRAP, exit 133);
#   - String::String() (src/Base.cpp) leaves its Buffer random.
# A stray loadMode is intermittent -- the same heap block is not always dirty
# -- which is why tools/check_schema_roundtrip.sh once read
# "MISMATCH item 0 backRefs[j]: a=0 b=5924" and then passed on rerun.
#
# HOW IT ASKS.  -schemaload on a corrupt-but-well-formed mutant must exit 22
# (src/Wposix.cpp maps a false RunSchemaLoad to 22). A trap on exit 133, or any
# other exit, means a heap registry began with a stray loadMode. -schematest
# must exit 0 with no MISMATCH line for the same reason, and it exercises
# Array/String construction on six more heap registries. Both are run many
# times (defaults 3000 loads, 200 tests) because the trigger is a dirty heap.
#
# THE GATE RUNS THE FULL DEFAULT: the trap rate is 3-18 per 3000 loads (roughly
# 0.1-0.6%), so a 60-load sample would miss a regression most of the time. The
# 3000-load default takes about 25 s, small next to the ~50-minute gate, so the
# marker takes no arguments and the gate runs the same loop a manual run does.
#
# Usage: tools/check_registry_flags.sh [--loads N] [--tests M] [--prove-red]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

LOADS=3000
TESTS=200
PROVE_RED=0
while [ $# -gt 0 ]; do
    case "$1" in
        --loads) LOADS="$2"; shift 2 ;;
        --tests) TESTS="$2"; shift 2 ;;
        --prove-red) PROVE_RED=1; shift ;;
        -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

if [ ! -x ./incursion-headless ]; then
    fail "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
fi

# --prove-red: delete the two initialisations, returning the constructor to
# the pre-fix state, rebuild, confirm the check goes red, restore the source
# and rebuild. Follows check_lib.sh's dance, but this check has no session and
# does not source that library. The mutation is the omission itself, not a
# forced true: forcing loadMode true in the global registry breaks the module
# compiler at build time, so the build would fail before the check could run.
if [ "$PROVE_RED" = 1 ]; then
    FROM='    LastUsedHandle = StartingHandle();
    saveMode = false;
    loadMode = false;
    reg_log = NULL;'
    TO='    LastUsedHandle = StartingHandle();
    reg_log = NULL;'
    KEEP="$(mktemp -d -t check_registry_flags)" || exit 2
    cp -p src/Registry.cpp "$KEEP/original" || { echo "could not copy source aside" >&2; exit 2; }
    _restore() {
        cp -p "$KEEP/original" src/Registry.cpp 2>/dev/null
        [ -f "$KEEP/original" ] && cmp -s "$KEEP/original" src/Registry.cpp \
            || echo "WARNING: src/Registry.cpp may not be restored; original at $KEEP/original" >&2
        rm -rf "$KEEP"
    }
    trap '_restore' EXIT INT TERM HUP
    python3 - "$FROM" "$TO" <<'PY' || { echo "the replacement failed" >&2; exit 2; }
import os, sys
p = "src/Registry.cpp"
s = open(p, encoding="utf-8", errors="surrogateescape").read()
a, b = sys.argv[1], sys.argv[2]
n = s.count(a)
if n != 1:
    sys.stderr.write("the text to replace appears %d times, want 1\n" % n)
    sys.exit(1)
open(p, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(a, b))
PY
    echo "  mutating src/Registry.cpp: removing the saveMode/loadMode initialisations"
    if ! BACKEND=posix ./build_macos.sh > "$KEEP/build.log" 2>&1; then
        tail -20 "$KEEP/build.log"
        fail "the mutated build failed; nothing is proved"
        exit 2
    fi
    echo "  re-running with the fix broken (full N, so the dirty-heap trigger lands)"
    if "$0" --loads 3000 --tests 200; then
        _restore
        trap - EXIT INT TERM HUP
        if ! BACKEND=posix ./build_macos.sh > /dev/null 2>&1; then
            fail "the check PASSED with the fix broken, and the restore build failed"
            exit 2
        fi
        fail "the check PASSED with the initialisations removed -- it measures nothing"
        exit 2
    fi
    INNER_FAILED=1
    echo "  restoring src/Registry.cpp and rebuilding"
    _restore
    trap - EXIT INT TERM HUP
    if ! BACKEND=posix ./build_macos.sh > /dev/null 2>&1; then
        fail "restored but the rebuild failed"
        exit 2
    fi
    [ "$INNER_FAILED" = 1 ] || exit 2
    echo "PROVED RED: removing the initialisations made the check fail"
    exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-regflags.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# One genuine v1 file for the crafting script to mutate, the way
# tools/check_v1_adversarial.sh does it.
if ! INCURSION_V1_RAW=1 ./incursion-headless -schematest "$WORK" -timeout 120 \
        < /dev/null > "$WORK/schematest.log" 2>&1; then
    tail -20 "$WORK/schematest.log"
    fail "-schematest could not produce the base file"
    exit 2
fi
BASE="$WORK/a.sav"
[ -f "$BASE" ] || { fail "no a.sav produced"; exit 2; }

if ! python3 tools/craft_bad_v1_saves.py "$BASE" "$WORK/mutants" \
        "$WORK/c.sav" "$WORK/e.sav" > "$WORK/craft.log" 2> "$WORK/craft.err"; then
    cat "$WORK/craft.err"
    fail "tools/craft_bad_v1_saves.py failed"
    exit 2
fi
MUTANT="$WORK/mutants/unterminated_version.sav"
[ -f "$MUTANT" ] || { fail "the crafting script produced no unterminated_version.sav"; exit 2; }

# ---------------------------------------------------------------- loads ---
LOADS_BAD=0
i=0
while [ "$i" -lt "$LOADS" ]; do
    i=$((i + 1))
    ./incursion-headless -schemaload "$MUTANT" -timeout 120 \
        < /dev/null > "$WORK/load.out" 2> "$WORK/load.err"
    STATUS=$?
    if [ "$STATUS" -ne 22 ]; then
        LOADS_BAD=$((LOADS_BAD + 1))
        if [ "$LOADS_BAD" -le 5 ]; then
            echo "  load #$i exited $STATUS, wanted 22 (a stray loadMode in a heap registry):"
            tail -5 "$WORK/load.err" | sed 's/^/    /'
        fi
    fi
done
if [ "$LOADS_BAD" -gt 0 ]; then
    fail "$LOADS_BAD of $LOADS -schemaload runs on unterminated_version.sav exited other than 22"
fi

# ---------------------------------------------------------------- tests ---
TESTS_BAD=0
MISMATCH=0
i=0
while [ "$i" -lt "$TESTS" ]; do
    i=$((i + 1))
    mkdir -p "$WORK/testout$i"
    ./incursion-headless -schematest "$WORK/testout$i" -timeout 120 \
        < /dev/null > "$WORK/test.out" 2>&1
    STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        TESTS_BAD=$((TESTS_BAD + 1))
        if [ "$TESTS_BAD" -le 5 ]; then
            echo "  -schematest #$i exited $STATUS, wanted 0:"
            tail -5 "$WORK/test.out" | sed 's/^/    /'
        fi
    fi
    if grep -q 'MISMATCH' "$WORK/test.out"; then
        MISMATCH=$((MISMATCH + 1))
        if [ "$MISMATCH" -le 5 ]; then
            echo "  -schematest #$i printed a MISMATCH line:"
            grep 'MISMATCH' "$WORK/test.out" | head -3 | sed 's/^/    /'
        fi
    fi
done
if [ "$TESTS_BAD" -gt 0 ]; then
    fail "$TESTS_BAD of $TESTS -schematest runs exited non-zero"
fi
if [ "$MISMATCH" -gt 0 ]; then
    fail "$MISMATCH of $TESTS -schematest runs printed a MISMATCH line"
fi

echo "loads: $LOADS run, $LOADS_BAD not exit 22"
echo "tests: $TESTS run, $TESTS_BAD non-zero exit, $MISMATCH MISMATCH lines"

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: the heap-built save-format registries start with zeroed mode flags"
    exit 0
fi
exit 1
