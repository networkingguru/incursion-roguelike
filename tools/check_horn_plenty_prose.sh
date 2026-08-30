#!/bin/bash
# Regression check for PA-08-F73 / inc-tek.8.8: the "Horn of Plenty"
# (AI_HORN Effect "Plenty" : EA_CREATION) entity must declare exactly ONE Desc
# field, and that surviving Desc must state the fatigue cost the EV_EFFECT
# handler charges (LoseFatigue(4)). The entity used to declare Desc TWICE -- a
# first Desc naming the fatigue cost and a second, fatigue-less duplicate; the
# duplicate is removed. Red while the block holds two Desc fields (or the sole
# Desc omits the fatigue cost), green once it holds exactly one Desc that names
# the fatigue cost.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Horn of Plenty block, from its header to its first
# two-space-indented closing brace.
block="$(sed -n '/AI_HORN Effect "Plenty" : EA_CREATION/,/^  }/p' "$SOURCE")"

# Count real Desc: fields (a Desc field line starts, after optional
# whitespace, with Desc:), so the upstream: comment that names "Desc" is
# excluded.
desc_count="$(printf "%s\n" "$block" | grep -c '^[[:space:]]*Desc:')"

if [ "$desc_count" -ne 1 ]; then
    echo "FAIL: the Horn of Plenty entity declares $desc_count Desc fields; it must declare exactly one (the duplicate fatigue-less Desc must be removed)."
    exit 1
fi

# Isolate the surviving Desc STRING and confirm it names the fatigue cost.
desc="$(printf "%s\n" "$block" | sed -n '/^[[:space:]]*Desc: "/,/";/p')"

if ! printf "%s\n" "$desc" | grep -q "fatigu"; then
    echo "FAIL: the Horn of Plenty surviving Desc does not name the fatigue cost the EV_EFFECT LoseFatigue(4) handler charges."
    exit 1
fi

echo "PASS: PA-08-F73 / inc-tek.8.8 the Horn of Plenty entity declares exactly one Desc, and it names the fatigue cost matching its LoseFatigue(4) code."
exit 0
