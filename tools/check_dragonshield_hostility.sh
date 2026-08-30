#!/bin/bash
# Regression check for PA-08-F79 / inc-tek.8.8: the Dragonshield angers only
# chromatic (evil) dragons, as its Desc promises ("Bearing a Dragonshield
# makes all chromatic dragons hostile to the bearer"), rather than every
# dragon. The shield's `and EA_GRANT` gives the bearer ENEMY_TO with a monster
# type in yval; LowPriorityStatiHostility (src/Target.cpp) tests
# me->isMType(that yval) for each dragon rating the bearer. A bare MA_DRAGON
# yval matches metallic (good) dragons too; the alignment-scoped compound
# MA_DRAGON+(MA_EVIL*256) makes isMType (src/Values.cpp) AND MA_DRAGON with
# MA_EVIL, so only evil dragons match. This check asserts the ENEMY_TO grant's
# yval names MA_EVIL and is NOT the bare, unconditional MA_DRAGON. RED while the
# grant angers all dragons, GREEN once it is alignment-scoped.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
block="$(sed -n '
  /^AI_SHIELD Effect "Dragonshield" : EA_BLAST/,/^AI_WEAPON Effect "Lightning;jav"/ {
    /^AI_WEAPON Effect "Lightning;jav"/q
    p
  }
' "$SOURCE")"

if [[ -z "$block" ]]; then
    echo "FAIL: could not find the Dragonshield block in $SOURCE."
    exit 1
fi

grant="$(printf '%s\n' "$block" | grep 'xval:[[:space:]]*ENEMY_TO')"
if [[ -z "$grant" ]]; then
    echo "FAIL: could not find the Dragonshield ENEMY_TO grant."
    exit 1
fi

# The grant must scope its hostility to evil (chromatic) dragons: the yval
# names MA_EVIL, not bare MA_DRAGON.
if ! printf '%s\n' "$grant" | grep -q 'MA_EVIL'; then
    echo "FAIL: the Dragonshield ENEMY_TO grant must scope its hostility to chromatic (evil) dragons -- its yval must name MA_EVIL (found: $grant)."
    exit 1
fi

# Guard against a regression to the unconditional form `yval: MA_DRAGON;`
# (bare MA_DRAGON with no alignment scope), which angers metallic dragons too.
if printf '%s\n' "$grant" | grep -Eq 'yval:[[:space:]]*MA_DRAGON[[:space:]]*;'; then
    echo "FAIL: the Dragonshield ENEMY_TO grant angers every dragon (bare yval: MA_DRAGON), not only chromatic ones (found: $grant)."
    exit 1
fi

echo "PASS: PA-08-F79 / inc-tek.8.8 Dragonshield angers only chromatic (evil) dragons."
exit 0
