#!/bin/bash
# Regression check for PA-08-F80 / inc-tek.8.8: the Hornblade carries no
# noise-making WQ_ROARING quality, which contradicts its concealment design.
# The hornblade is a disguised stealth weapon -- its Desc says it "is so
# difficult to visually recognize as a weapon" that its first strike on any
# given foe counts as a sneak attack, and its EF_HIDEQUAL flag hides its
# qualities from the player. A "roaring" quality has no place on it, and
# WQ_ROARING is inert anyway (no src/ code keys behaviour on it; it lives only
# in the name/const tables), so removing it is a no-op the player never sees.
# This check asserts the Hornblade entity block declares no WQ_ROARING. RED
# while the block still lists WQ_ROARING, GREEN once it is gone.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
block="$(sed -n '
  /^AI_WEAPON Effect "Hornblade" : EA_GENERIC/,/^AI_WEAPON Effect "Dwarven Thrower"/ {
    /^AI_WEAPON Effect "Dwarven Thrower"/q
    p
  }
' "$SOURCE")"

if [[ -z "$block" ]]; then
    echo "FAIL: could not find the Hornblade block in $SOURCE."
    exit 1
fi

# The Hornblade must declare no noise-making WQ_ROARING quality. Drop full-line
# // comments first: the upstream: mark left at the fix site names WQ_ROARING in
# its prose, and that mention must not be read as a live declaration.
if printf '%s\n' "$block" | grep -v '^[[:space:]]*//' | grep -q 'WQ_ROARING'; then
    echo "FAIL: the Hornblade still declares WQ_ROARING, a noise-making quality that contradicts its concealment design."
    exit 1
fi

echo "PASS: PA-08-F80 / inc-tek.8.8 the Hornblade carries no WQ_ROARING quality."
exit 0
