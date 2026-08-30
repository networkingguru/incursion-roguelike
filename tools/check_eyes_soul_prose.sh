#!/bin/bash
# Regression check for PA-08-F81 / inc-tek.8.8: the "Eyes of the Soul" (entity
# "the Soul;eyes") description must document the item's fourth grant, EXTRA_FEAT
# FT_NECROPHYSIOLOGY. The Desc long described only the Intimidate/Knowledge
# (Theology) skill bonus and the fear-save bonus, and never mentioned the
# Necrophysiology feat the item also grants -- the feat that lets its holder
# score critical hits against undead (src/FeatTab.cpp, src/Fight.cpp). Red while
# the Desc omits the feat, green once the Desc names Necrophysiology.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Eyes of the Soul block, then extract the Desc STRING itself (from
# 'Desc: "' to its first closing '";'), so the upstream: comment that names the
# feat -- it sits above the Desc line -- is not read as the Desc naming it.
block="$(sed -n '/AI_EYES Effect "the Soul;eyes"/,/AI_BOOTS Effect "Stability;boots"/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if [ -z "$desc" ]; then
    echo "FAIL: could not find the Eyes of the Soul Desc in $SOURCE; the anchor changed."
    exit 1
fi

if printf "%s\n" "$desc" | grep -q "Necrophysiology"; then
    echo "PASS: PA-08-F81 / inc-tek.8.8 the Eyes of the Soul description names the Necrophysiology feat the item grants."
    exit 0
fi

echo "FAIL: the Eyes of the Soul description omits the Necrophysiology feat, yet the item grants EXTRA_FEAT FT_NECROPHYSIOLOGY."
exit 1
