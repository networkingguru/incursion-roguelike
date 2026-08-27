#!/bin/bash
# Regression check for F49 / inc-tek.8.8: the Horn of Goodness' protective
# Magic Circle vs. Evil field has the 60-foot (six-square) promised radius.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
effect="$(sed -n '/^AI_HORN Effect "Goodness"/,/^  }/p' "$SOURCE")"
new_field="$(printf '%s\n' "$effect" | grep -A1 'NewField' | tr '\n' ' ' || true)"

printf '%s\n' "$new_field" | grep -Eq ',[[:space:]]*6[[:space:]]*,[[:space:]]*GLYPH_VALUE' || {
    echo "FAIL: the Horn of Goodness protective field does not use radius 6."
    exit 1
}

echo "PASS: F49 / inc-tek.8.8 Horn of Goodness protective field uses radius 6."
