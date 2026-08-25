#!/bin/bash
# Round-trip check for the v1 save schema (docs/SAVE-SCHEMA-SPEC.md).
# Drives `incursion-headless -schematest`, which runs one section per class
# group. Each section builds objects through the LoadGroup allocation idiom,
# fills every member with a distinct value, writes them as a v1 group, reads
# the file back into a fresh registry, compares field for field, writes a
# second file and byte-compares the two. DEBUG builds also run the coverage
# check on every record and any finding is fatal.
#
#   items     four Item objects (class Item exactly) with real module rIDs in
#             iID/eID/homeID, stati, a name and backRefs.
#   creature  one Monster: every Creature member, and three live targets in
#             ts of types TargetEnemy, TargetArea and TargetItem.
#   character one Player and one Monster: Character's and Player's own
#             members, including every rID-bearing one (ClassID, RaceID,
#             GodID, Tattoos, Macros), both journal strings, the timing
#             block and the option array; and Monster's own four members.
#   feature   one each of Feature, Door, Trap and Portal, with fID/tID
#             pointing at real module resources.
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
for g in items creature character feature; do
    grep -q "^SCHEMATEST GROUP $g PASS" "$WORK/out.txt" ||
        fail "no 'SCHEMATEST GROUP $g PASS' line"
done
grep -q "byte-identical" "$WORK/out.txt" || fail "second save was not byte-compared"
if grep -q "SCHEMA COVERAGE" "$WORK/out.txt"; then
    grep "SCHEMA COVERAGE" "$WORK/out.txt"; fail "coverage findings"
fi
[ "$FAILED" -eq 0 ] && { echo "PASS: v1 round trip (Item, Creature, Character and Feature chains) is exact"; exit 0; }
exit 1
