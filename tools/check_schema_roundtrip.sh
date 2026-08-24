#!/bin/bash
# Round-trip check for the v1 save schema, phase 1 (docs/SAVE-SCHEMA-SPEC.md).
# Drives `incursion-headless -schematest`, which: loads the modules, builds a
# set of Item objects (class Item exactly, via the LoadGroup allocation idiom)
# with real module rIDs in iID/eID/homeID, stati, a name and backRefs; writes
# them as a v1 group; reads the file back into a fresh registry; compares every
# field; writes a second file; and byte-compares the two. DEBUG builds also run
# the coverage check on every record and any finding is fatal.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
FAILED=0; fail() { echo "FAIL: $1"; FAILED=1; }
[ -x ./incursion-headless ] || { echo "FAIL: build first: BACKEND=posix ./build_macos.sh"; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-schema.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# < /dev/null + -timeout: a binary that predates the flag would otherwise start
# an ordinary interactive session and hang (src/Wposix.cpp:549-558); the
# redirect is the tools/check_dump_save.sh:46-47 idiom.
if ! ./incursion-headless -schematest "$WORK" -timeout 120 < /dev/null > "$WORK/out.txt" 2>&1; then
    tail -30 "$WORK/out.txt"
    fail "-schematest exited non-zero"
fi
grep -q "^SCHEMATEST PASS" "$WORK/out.txt" || fail "no 'SCHEMATEST PASS' line"
grep -q "byte-identical" "$WORK/out.txt" || fail "second save was not byte-compared"
if grep -q "SCHEMA COVERAGE" "$WORK/out.txt"; then
    grep "SCHEMA COVERAGE" "$WORK/out.txt"; fail "coverage findings"
fi
[ "$FAILED" -eq 0 ] && { echo "PASS: v1 round trip (Item chain) is exact"; exit 0; }
exit 1
