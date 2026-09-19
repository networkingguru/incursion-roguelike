#!/bin/bash
# gate: live
# Regression check for inc-7ml0: TextTerm::ReadLine (src/Term.cpp:3249) wrote
# every typed character into `char Input[160]` (inc/Term.h:326) with no bound
# on the index (`Input[loc++] = (char)ch`, src/Term.cpp:3277), so the 161st
# character -- and the Enter key's terminating NUL right after it -- land
# outside the buffer. Reachable from ordinary play, no wizard mode: [D]isplay
# Character then [W]rite Dump (src/Managers.cpp:2500-2509) reaches the same
# ReadLine directly, and its typed text becomes the base name of the file it
# writes under logs/ -- see tools/keys/readline-overflow.keys for why that
# script uses this path rather than the bead's own KY_CMD_JOURNAL example.
#
# tools/keys/readline-overflow.keys types 161 'x' -- one more than Input can
# hold -- as a dump filename, proves the prompt still works for an ordinary
# name afterward, then leaves the sheet. This check reads two kinds of
# evidence out of that run:
#
#   1. CONTENT (needs only ./incursion-headless). The longest run of 'x' in
#      any logs/*.txt filename is at most 159 -- sizeof(Input) - 1, the most
#      a routine that leaves room for the terminating NUL can ever store --
#      on a fixed build, and 161 (everything typed) on an unfixed one.
#   2. STRUCTURE (needs ./incursion-ubsan, EXTRA_CXXFLAGS="-fsanitize=undefined
#      -g" EXTRA_LDFLAGS=-fsanitize=undefined BACKEND=posix OUT=incursion-ubsan
#      ./build_macos.sh, recipe at build_macos.sh:142-143). UndefinedBehavior-
#      Sanitizer reports "index N out of bounds for type 'char[160]'" at
#      src/Term.cpp on an unfixed build and nothing on a fixed one. This is
#      the half the content check cannot give by itself: proof that the WRITE
#      never crosses the line, not just that nothing looked wrong afterward.
#
# 1 alone is already a fail/pass signal; 2 is skipped (not required) when
# ./incursion-ubsan is not built, so an ordinary run of this check costs one
# build.
#
# Usage: tools/check_readline_overflow.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS="tools/keys/readline-overflow.keys"
OPTS="tools/fixtures/options-2026-08-22.dat"
LOAD="tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav"
CAP=159   # sizeof(Input) - 1: room for typed characters plus the NUL

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

FAIL=0
WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-readline.XXXXXX")"
UBWORK=""
trap 'rm -rf "$WORK" "$UBWORK"' EXIT

# --- 1. content: how long a run of 'x' actually landed in a dumped filename ---
INCURSION_RUN_DIR="$WORK/game" \
    INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > "$WORK/out" 2>&1
STATUS=$?

DUMPDIR="$WORK/game/logs"
LONGEST="$(ls "$DUMPDIR" 2>/dev/null | grep -oE 'x+' | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"
if [ -z "$LONGEST" ] || [ "$LONGEST" -eq 0 ]; then
    echo "INCONCLUSIVE: no logs/*x* file appeared (session exit $STATUS) -- the"
    echo "              161 typed characters never reached DumpCharacter()."
    tail -20 "$WORK/out"
    exit 2
fi

if ! ls "$DUMPDIR" 2>/dev/null | grep -q "^stillusable\.txt$"; then
    echo "FAIL: the second, ordinary-length dump ('stillusable.txt') is"
    echo "      missing -- the prompt did not stay usable after the"
    echo "      overflowing one."
    FAIL=1
fi

if [ "$LONGEST" -gt "$CAP" ]; then
    echo "FAIL: logs/ holds a file name with a run of $LONGEST 'x' characters,"
    echo "      more than the $CAP TextTerm::ReadLine's buffer can hold and"
    echo "      still leave room for its terminating NUL -- Input[160] was"
    echo "      written past."
    FAIL=1
fi

# --- 2. structure: did the write itself ever cross the bound? ---
if [ -x ./incursion-ubsan ]; then
    NEWER="$(find src inc -type f -newer ./incursion-ubsan -print -quit)"
    if [ -n "$NEWER" ]; then
        echo "INCONCLUSIVE: ./incursion-ubsan is older than $NEWER, so it would"
        echo "              test old code. Rebuild it: EXTRA_CXXFLAGS=\"-fsanitize=undefined -g\" EXTRA_LDFLAGS=-fsanitize=undefined BACKEND=posix OUT=incursion-ubsan ./build_macos.sh"
        FAIL=1
    else
        UBWORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-readline-ubsan.XXXXXX")"
        UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=0:halt_on_error=0}" \
        INCURSION_RUN_DIR="$UBWORK/game" \
            INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$LOAD" \
            INCURSION_BIN=./incursion-ubsan \
            tools/headless.sh "$KEYS" "$SEED" > "$UBWORK/out" 2>&1
        if grep -qE "src/Term\.cpp:[0-9]+:[0-9]+: runtime error: index [0-9]+ out of bounds for type 'char\[160\]'" "$UBWORK/out"; then
            echo "FAIL: UndefinedBehaviorSanitizer caught TextTerm::ReadLine writing"
            echo "      Input[] out of bounds:"
            grep -E "index [0-9]+ out of bounds for type 'char\[160\]'" "$UBWORK/out"
            FAIL=1
        fi
    fi
else
    echo "NOTE: ./incursion-ubsan not built, so the structural half did not run."
    echo "      Build it: EXTRA_CXXFLAGS=\"-fsanitize=undefined -g\" EXTRA_LDFLAGS=-fsanitize=undefined BACKEND=posix OUT=incursion-ubsan ./build_macos.sh"
fi

if [ "$FAIL" -ne 0 ]; then
    echo "Run dir: $WORK"
    exit 1
fi

echo "PASS: the longest 'x' run in a dumped file name is $LONGEST of $CAP allowed,"
echo "      the second dump ('stillusable.txt') exists intact, and UBSan (when"
echo "      built) reported no out-of-bounds write to Input[]."
echo "Run dir: $WORK"
exit 0
