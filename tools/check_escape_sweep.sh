#!/bin/bash
# Regression check for the port's backslash sweep (inc-49m, inc-upw.28).
#
# WHY THIS EXISTS. The port replaced Win32 path separators with forward slashes
# by mechanical substitution, and the substitution could not tell a path from an
# escape. Where the source said \\n -- a literal backslash and an n, which is
# what a generated IncursionScript resource needs -- it wrote /n, which is not
# an escape at all and reaches the reader verbatim. Six sites in
# BuildSpellList() (src/Main.cpp) were damaged that way and nobody noticed for
# nine months, because the block behind BUILD_SPELL_LIST never compiles. The
# same sweep also flattened an #ifdef WIN32 in src/Player.cpp until both its
# branches were identical, and swapped <io.h> for <unistd.h> inside a guard that
# admits only the platform where unistd.h does not exist (src/Tokens.cpp).
#
# Attention did not find these; a person reading the diff three separate times
# found three of them and missed three more. A grep finds all six every time.
#
# WHAT IT CATCHES. A forward slash where a C escape belongs, inside a double
# quoted string: /n /t /r /0 not followed by a word character. On the tree as it
# stands that pattern has exactly zero innocent matches, which is what makes it
# usable as a gate.
#
# WHAT IT DOES NOT CATCH, and there is no cheap way to make it:
#   - a swapped header or a collapsed #ifdef, which are the sweep's other two
#     shapes. Compare against the import (7b8504a) by hand for those.
#   - ASCII art whose slant is now wrong. The gravestone (src/Main.cpp) lost its
#     right-hand wall to this sweep and was fixed by eye in commit 61ce748;
#     nothing here would have seen it, because '/' inside a picture is legal.
#
# Usage: tools/check_escape_sweep.sh              (exits 0 on pass, 1 on fail)
#        tools/check_escape_sweep.sh --selftest   (proves the scan bites)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# One place, used by the check and by the selftest, so the selftest cannot pass
# on a pattern the check does not run.
scan() { # <file>...
    grep -nE '"[^"]*/(n|t|r|0)([^a-zA-Z0-9_./-]|")' "$@" 2>/dev/null
}

if [ "${1:-}" = "--selftest" ]; then
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-sweep.XXXXXX")"
    trap 'rm -rf "$WORK"' EXIT
    ok=0

    # The exact damage, as it stood in src/Main.cpp before the fix.
    printf 'void f(void) {\n  fprintf(f1,"\\n\\n      /n/n\\n      <7>%%s (<1>", name);\n}\n' \
        > "$WORK/broken.c"
    if scan "$WORK/broken.c" > /dev/null; then
        echo "  scan finds the damage it was written for: good"
    else
        echo "SELFTEST FAIL: the scan did not find /n/n in a string literal"
        ok=1
    fi

    # The same line, repaired. A scan that fires here would fire on the whole
    # tree and the gate would have to be switched off, which is how a gate dies.
    printf 'void f(void) {\n  fprintf(f1,"\\n\\n      \\\\n\\\\n\\n      <7>%%s (<1>", name);\n}\n' \
        > "$WORK/fixed.c"
    if scan "$WORK/fixed.c" > /dev/null; then
        echo "SELFTEST FAIL: the scan fired on a correctly escaped literal"
        scan "$WORK/fixed.c"
        ok=1
    else
        echo "  scan leaves a correctly escaped literal alone: good"
    fi

    # A path really does contain a slash, and paths are what the sweep was for.
    printf 'const char *p = "mod/Incursion.Mod";\nconst char *q = "%%s/dispatch.h";\n' \
        > "$WORK/paths.c"
    if scan "$WORK/paths.c" > /dev/null; then
        echo "SELFTEST FAIL: the scan called a legitimate path a broken escape"
        scan "$WORK/paths.c"
        ok=1
    else
        echo "  scan leaves a real path alone: good"
    fi

    [ "$ok" -eq 0 ] && echo "PASS: the scan bites" && exit 0
    exit 1
fi

HITS="$(scan src/*.c src/*.cpp inc/*.h)"
if [ -n "$HITS" ]; then
    echo "$HITS"
    echo "FAIL: a forward slash sits where a C escape belongs. The port's path"
    echo "      sweep did this to six sites in src/Main.cpp; see inc-49m."
    exit 1
fi

echo "PASS: no string literal spells an escape with a forward slash"
exit 0
