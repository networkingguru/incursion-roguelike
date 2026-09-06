#!/bin/bash
# Structural regression check for inc-fiiq: reference cleanup must narrow
# removal to the rows that refer to the dying source, and must keep the inline
# fallback that guarantees forward progress.
#
# The EV_REMOVED event is NOT what this check defends. The base code's
# StatiIter_RemoveCurrent (inc/Map.h) already delivered it, and a clean HEAD
# build was measured firing the same handler. What HEAD gets wrong is the
# BREADTH of the removal: it reaps every row sharing the effect id.
#
# This stays structural because the narrowing's behavioural oracles live in
# check_circle_creator_death.sh and check_overlapping_modifier_fields.sh, and
# the fallback guards a livelock nobody has reproduced.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

body="$(sed -n '/void Thing::__StatiRemoval(Status \*S, Thing \*t)/,/^}/p' src/Status.cpp)"
fail=0

if ! printf '%s\n' "$body" | grep -q \
    'if (S->eID && RES(S->eID)->Type == T_TEFFECT)'; then
    echo "FAIL: effect rows are not distinguished during reference cleanup."
    fail=1
fi
if ! printf '%s\n' "$body" | grep -q \
    't->RemoveEffStati(S->eID, EV_REMOVED, 0, this)'; then
    echo "FAIL: effect cleanup does not deliver EV_REMOVED narrowed to the dying source."
    fail=1
fi
if ! printf '%s\n' "$body" | grep -q \
    'if (S->Nature && S->h == myHandle)'; then
    echo "FAIL: effect cleanup has no source-row fallback for forward progress."
    fail=1
fi
inline_count="$(printf '%s\n' "$body" | grep -c 'Stati_RemoveInline(S,t)')"
if [ "$inline_count" -ne 2 ]; then
    echo "FAIL: expected inline removal in the effect fallback and non-effect path; found $inline_count."
    fail=1
fi

echo "cleanup: event=source-narrowed fallback=source-checked inline-paths=$inline_count"
[ "$fail" -eq 0 ] || exit 1
echo "PASS: reference cleanup narrows removal to the dying source and guarantees progress."
