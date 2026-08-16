#!/bin/bash
# Verify that every base-code bug we have fixed is marked, and marked completely.
#
# The rule is in AGENTS.md and CLAUDE.md: a fix to a defect that is upstream's
# rather than the port's carries an 'upstream:' comment at the fix site and a row
# in the "Base-code bugs fixed locally" table in docs/REPORTING-GATE.md. The
# point is that if the original maintainer ever returns, the work is findable.
#
# WHAT THIS CAN CHECK. That each marker states the four required things, and
# that its tracking id reaches the registry. That is the failure that actually
# happens: somebody marks the code, and the table never hears about it.
#
# WHAT THIS CANNOT CHECK, and do not let a PASS tell you otherwise:
#   - whether the provenance claim is TRUE. Deciding that a defect would also
#     misbehave on Win32 with the original typedefs is a judgement, and a wrong
#     one mislabels our port artefact as upstream's bug. Only a human reading
#     the code can settle it.
#   - whether an UNMARKED fix should have been marked. Nothing here knows which
#     diffs were bug fixes. That gap is the reason the rule lives in AGENTS.md
#     and CLAUDE.md, where every agent reads it, rather than only in this script.
#
# Usage: tools/check_upstream_marks.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REGISTRY="docs/REPORTING-GATE.md"
FAIL=0

[ -f "$REGISTRY" ] || { echo "FAIL: $REGISTRY is missing"; exit 1; }

# A check that cannot find the code must FAIL, never pass quietly. Without this
# guard, running the script from anywhere but the repository reports "no markers
# found" and exits 0 -- a green result from a run that examined nothing. That is
# the same mistake as counting a session that never entered a map as a pass
# (inc-loa.3), and it was caught by testing this script's own failure path.
for d in src inc; do
    [ -d "$d" ] || { echo "FAIL: no $d/ directory under $ROOT; nothing was examined"; exit 1; }
done

MARKS="$(grep -rn "upstream:" src inc 2>/dev/null | grep -v "^Binary")"

if [ -z "$MARKS" ]; then
    echo "No 'upstream:' markers found in src/ or inc/."
    echo "That is not automatically a pass. Most defects in this codebase are"
    echo "upstream's, so zero markers more likely means the rule is being"
    echo "forgotten than that no base-code bug has ever been fixed. See inc-iqh."
    exit 0
fi

COUNT=0
while IFS= read -r hit; do
    FILE="${hit%%:*}"
    REST="${hit#*:}"
    LINE="${REST%%:*}"
    COUNT=$((COUNT + 1))

    # The marker is a comment block. Twenty lines is comfortably more than any
    # written so far and stops well short of the next function.
    BLOCK="$(sed -n "${LINE},$((LINE + 20))p" "$FILE")"

    label="$FILE:$LINE"

    # 2. evidence tier, in the words docs/REPORTING-GATE.md uses.
    if ! echo "$BLOCK" | grep -qE "Observed|Traced|Reasoned"; then
        echo "FAIL: $label states no evidence tier (Observed, Traced or Reasoned)"
        FAIL=1
    fi

    # 3. tracking id, and it must reach the registry.
    ID="$(echo "$BLOCK" | grep -oE "inc-[a-z0-9]+(\.[0-9]+)*" | head -1)"
    if [ -z "$ID" ]; then
        echo "FAIL: $label names no tracking id"
        FAIL=1
    elif ! grep -q "$ID" "$REGISTRY"; then
        echo "FAIL: $label is tracked as $ID, which has no row in $REGISTRY"
        echo "      Add it to the 'Base-code bugs fixed locally' table."
        FAIL=1
    fi

    # 4. sent, or not sent. Either is fine; silence is not.
    if ! echo "$BLOCK" | grep -qiE "sent|submitted|filed upstream"; then
        echo "FAIL: $label does not say whether it has been sent upstream"
        FAIL=1
    fi
done <<< "$MARKS"

echo
if [ "$FAIL" -ne 0 ]; then
    echo "UPSTREAM MARKS INCOMPLETE: $COUNT marker(s) checked"
    exit 1
fi
echo "PASS: $COUNT upstream marker(s), all complete and all in $REGISTRY"
exit 0
