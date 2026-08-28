#!/bin/bash
# Structural regression check for bd inc-x1f3.
#
# Creature::Devour(Corpse * c) (src/Skills.cpp) builds a fake Monster from the
# corpse's mID to score the meal, then copies TEMPLATE stati onto it so a
# templated corpse (celestial, fiendish, half-dragon, pseudonatural, ...) grants
# the template's resistances and attributes when devoured. Those templates live
# on the CORPSE (Corpse::Corpse copies them onto itself, src/Item.cpp), and every
# sibling consumer reads them back off the corpse -- Sacrifice (src/Prayer.cpp)
# and the burning-hunger eat (src/Item.cpp) both iterate the corpse c.
#
# The bug: ww's Devour iterated `this` (the EATER) instead of `c` (the corpse),
# so the corpse's template resistances were silently dropped and the eater's own
# templates were wrongly applied. StatiIterNature/StatiIterEnd also bump a Nested
# counter on their argument, so the open and close MUST name the same object.
#
# This check re-reads the Devour(Corpse*) body and fails if the template
# iteration ever points back at `this` again, or if the open/close disagree.
#
# Usage: tools/check_devour_template_source.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Extract the Devour(Corpse*) function body: from its signature to the closing
# brace of the function (the first line that is a lone '}' at column 0).
body="$(awk '
  /^void Creature::Devour\(Corpse \* c\) \{/ { in_fn=1 }
  in_fn { print }
  in_fn && /^}/ { exit }
' src/Skills.cpp)"

[ -n "$body" ] || {
    echo "FAIL: could not find Creature::Devour(Corpse * c) in src/Skills.cpp."
    echo "      Its signature may have changed; update this check to match."
    exit 1
}

fail=0

# The template iteration must read the corpse c, not the eater this.
if printf '%s\n' "$body" | grep -qE 'StatiIterNature\(this,[[:space:]]*TEMPLATE\)'; then
    echo "FAIL: Devour(Corpse*) iterates the EATER's templates: StatiIterNature(this, TEMPLATE)."
    echo "      A corpse stores its templates on itself; iterate the corpse c, as"
    echo "      Sacrifice (src/Prayer.cpp) and burning-hunger eat (src/Item.cpp) do."
    fail=1
fi

if ! printf '%s\n' "$body" | grep -qE 'StatiIterNature\(c,[[:space:]]*TEMPLATE\)'; then
    echo "FAIL: Devour(Corpse*) no longer iterates the corpse's templates:"
    echo "      expected StatiIterNature(c, TEMPLATE)."
    fail=1
fi

# Open and close must name the same object, or the Nested counter is corrupted
# on both the corpse and the eater.
if ! printf '%s\n' "$body" | grep -qE 'StatiIterEnd\(c\)'; then
    echo "FAIL: the TEMPLATE iteration in Devour(Corpse*) does not close on the"
    echo "      same object it opened on (expected StatiIterEnd(c))."
    echo "      StatiIterNature/StatiIterEnd bump a Nested counter on their"
    echo "      argument; a mismatched pair corrupts it."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: Devour(Corpse*) scores the meal off the corpse's templates (c),"
    echo "      opening and closing the iteration on the same object."
fi
exit "$fail"
