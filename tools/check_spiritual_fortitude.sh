#!/bin/bash
# gate: cheap
# Structural regression check for inc-vb9n (PA-07-F10).
#
# The defect: the attribute-drain case of Creature::Damage (src/Fight.cpp)
# reduced incoming drain by the SUSTAIN magnitude for the drained attribute
# alone --
#
#     if (e.EVictim->HasStati(SUSTAIN,at))
#         e.vDmg = max(0,e.vDmg - e.EVictim->SumStatiMag(SUSTAIN,at));
#
# -- and never counted SUSTAIN for A_AID, the attribute the Priest spell
# Spiritual Fortitude grants (lib/pspells.irh: `xval: SUSTAIN; yval: A_AID;
# pval: +2`) so that it "sustains all your attributes (by +2)". With A_AID
# uncounted the spell protected nothing from a draining touch.
#
# This check is structural: it reads the source text at the drain site and
# requires the reduction to include SumStatiMag(SUSTAIN,A_AID). It does not
# run the game. The A/B gameplay oracle lives in the bead; a headless
# behavioural check remains the goal.
#
# The file may be overridden so the same check can be pointed at another copy
# (for example the HEAD version, to prove it is red before the fix):
#     FIGHT_CPP=<path> tools/check_spiritual_fortitude.sh
#
# Usage: tools/check_spiritual_fortitude.sh    (0 pass, 1 fail, 2 could not measure)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2

src="${FIGHT_CPP:-src/Fight.cpp}"

[ -f "$src" ] || { echo "COULD NOT MEASURE: $src not found."; exit 2; }

# Locate the attribute-drain SUSTAIN reduction. It is the only place the drain
# case reads SUSTAIN for the drained attribute (`at`); the experience-drain
# branch reads SUSTAIN for A_AID and is deliberately not this site.
site="$(grep -n "SumStatiMag(SUSTAIN,at)" "$src" || true)"
[ -n "$site" ] || {
    echo "FAIL: the attribute-drain SUSTAIN reduction has gone from $src."
    echo "      Expected a read of SumStatiMag(SUSTAIN,at) at the drain site."
    exit 1
}

count="$(printf '%s\n' "$site" | wc -l | tr -d ' ')"
[ "$count" = "1" ] || {
    echo "FAIL: expected exactly one SumStatiMag(SUSTAIN,at) drain site, found $count:"
    printf '%s\n' "$site"
    exit 1
}
lineno="${site%%:*}"

# The reduction spans the site line and a few lines around it. Require the
# A_AID magnitude to be summed into the same reduction.
block="$(sed -n "$((lineno-8)),$((lineno+8))p" "$src")"
if ! grep -q "SUSTAIN,A_AID" <<< "$block"; then
    echo "FAIL: the attribute-drain reduction does not count SUSTAIN for A_AID."
    echo "      At $src:$lineno the reduction reads only SUSTAIN,at, so Spiritual"
    echo "      Fortitude (SUSTAIN/A_AID) protects nothing from a draining touch."
    echo "      Sum SumStatiMag(SUSTAIN,A_AID) into the reduction. See inc-vb9n."
    exit 1
fi

# Guard against a reversion that reintroduces the unguarded HasStati form: the
# reduction must subtract a magnitude, not silently skip a second call.
if grep -q "e.vDmg - e.EVictim->SumStatiMag(SUSTAIN,A_AID)" <<< "$block" \
   || ! grep -q "max(0,e.vDmg - sus)" <<< "$block"; then
    echo "FAIL: the A_AID term is present but the reduction is not the expected"
    echo "      combined form. At $src:$lineno expected"
    echo "        sus = SumStatiMag(SUSTAIN,at) + SumStatiMag(SUSTAIN,A_AID);"
    echo "        if (sus > 0) e.vDmg = max(0,e.vDmg - sus);"
    echo "      See inc-vb9n."
    exit 1
fi

echo "PASS: the attribute-drain SUSTAIN reduction counts both the drained"
echo "      attribute and A_AID (Spiritual Fortitude). $src:$lineno"
exit 0
