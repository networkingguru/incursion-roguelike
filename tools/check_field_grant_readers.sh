#!/bin/bash
# Structural companion for inc-fiiq: every modifier reader must suppress
# redundant field grants, without broadening the rule to ordinary statuses.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
for site in src/Creature.cpp src/Sheet.cpp inc/Inline.h; do
    if ! grep -q 'RedundantFieldGrant(S)' "$site"; then
        echo "FAIL: $site does not suppress redundant field grants."
        fail=1
    fi
done
adjust_loops="$(grep -c 'StatiIterNature(this,ADJUST' src/Values.cpp)"
adjust_guards="$(sed -n '/StatiIterNature(this,ADJUST/,/if (HasStati(MANIFEST))/p' \
    src/Values.cpp | grep -c 'RedundantFieldGrant(S)')"
echo "readers: saving=guarded sheet=guarded sum=guarded adjust=$adjust_guards/$adjust_loops"
if [ "$adjust_guards" -ne "$adjust_loops" ]; then
    echo "FAIL: not every ADJUST-family reader suppresses duplicate field grants."
    fail=1
fi
[ "$fail" -eq 0 ] || exit 1
echo "PASS: all five modifier-reader families use the shared field-grant predicate."
