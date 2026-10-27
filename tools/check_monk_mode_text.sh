#!/bin/bash
# gate: cheap
# Regression check for inc-lhb: the Monk Preferred Attack Form option text
# (OPT_MONK_MODE, src/Tables.cpp) must describe NATURAL mode's bonus as damage
# only, matching ListAttacks (src/Creature.cpp), which adds (level+1)/2 to
# natural-attack damage and touches no speed. The code wins (owner ruling).
# Red while the entry says "speed" or lacks "+1 bonus to damage for every odd
# monk level"; green once it says that and no "speed". The upstream: comment
# above the entry is excluded, so its own mention of speed does not count.
# fact: src/Tables.cpp OPT_MONK_MODE entry text -- static source file, read from disk; no run, no roll, so no seed control applies
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-src/Tables.cpp}"
entry="$(sed -n '/[{] OPT_MONK_MODE,/,/},[[:space:]]*$/p' "$SOURCE")"

if [ -z "$entry" ]; then
    echo "FAIL: inc-lhb the OPT_MONK_MODE entry was not found in $SOURCE, so its text cannot be judged."
    exit 1
fi

if grep -qi 'speed' <<<"$entry"; then
    echo "FAIL: inc-lhb the OPT_MONK_MODE text still mentions speed, but ListAttacks adds the monk bonus to damage only."
    exit 1
fi

if ! grep -qF '+1 bonus to damage for every odd monk level' <<<"$entry"; then
    echo "FAIL: inc-lhb the OPT_MONK_MODE text lacks \"+1 bonus to damage for every odd monk level\"."
    exit 1
fi

echo "PASS: inc-lhb the OPT_MONK_MODE text describes the NATURAL-mode bonus as damage only, matching ListAttacks."
exit 0
