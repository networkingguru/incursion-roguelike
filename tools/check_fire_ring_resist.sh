#!/bin/bash
# Regression check for PA-08-F57 / inc-tek.8.8: the Ring of Elemental
# Command (Fire) grants Fire Resistance 10, matching its description.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
effect="$(sed -n '
  /^AI_RING Effect "Elemental Command (Fire)" : EA_GRANT/,/^AI_RING Effect "Elemental Command (Water)"/ {
    /^AI_RING Effect "Elemental Command (Water)"/q
    p
  }
' "$SOURCE")"
value="$(printf '%s\n' "$effect" | sed -nE 's/.*xval:[[:space:]]*RESIST;[[:space:]]*yval:[[:space:]]*AD_FIRE;[[:space:]]*pval:[[:space:]]*([-+]?[0-9]+).*/\1/p')"

if [[ "$value" != "10" ]]; then
    echo "FAIL: Ring of Elemental Command (Fire) Fire Resistance must be 10; found '${value:-<missing>}'."
    exit 1
fi

echo "PASS: PA-08-F57 / inc-tek.8.8 Fire ring grants Fire Resistance 10."
