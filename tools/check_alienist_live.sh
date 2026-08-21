#!/bin/bash
# Regression check for bd inc-tek.8.3 finding PA-03-F7: the Alienist's
# "Surreal Presence" effect was fully written and never granted.
#
# The class's prose promises, at 3rd level, "the benefit (or curse) of a
# constantly active spook spell as an innate supernatural ability"
# (lib/prestige.irh:293-296), and the effect that does exactly that sat at
# lib/prestige.irh:449-461 with nothing in the ruleset referring to it -- no
# Grants entry, no ThrowEff, no GainPermStati. The fix adds two lines to the
# class's own EV_ADVANCE handler.
#
# THE ORACLE, and why it is this and not the character sheet. Surreal
# Presence is not a stati on the Alienist. It is a mobile field around her
# (rval FI_MODIFIER|FI_MOBILE, aval AR_MFIELD) and she is immune to her own
# (EF_CASTER_IMMUNE), so neither her sheet nor her stati list mentions it --
# this was checked, on a live Alienist 5, through wizard mode's Examine
# Player Data. What the field does is speak: a creature that enters it fires
# the effect's EV_FIELDON message, which an onlooker reads as
# "The <EActor> seems unsettled."
#
# tools/keys/prestige-alienist.keys summons a kobold beside her, which puts
# it inside the field on the turn it appears. On a module compiled from the
# pre-fix lib/prestige.irh the same summon produces no message at all.
#
# Usage: tools/check_alienist_live.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=5
KEYS=tools/keys/prestige-alienist.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCR="$RUN/logs/screens/0001-field.txt"

if [ ! -f "$SCR" ]; then
    echo "FAIL: the screen dump was never taken -- the character never got"
    echo "      as far as summoning anything."
    echo "$OUT" | tail -10
    exit 1
fi

fail=0

# Guard first. If the build stops producing an Alienist -- because a class
# was added to lib/ and the prestige menu moved, or an entry requirement
# changed -- the assertion below would fail for the wrong reason.
if ! grep -q "Alienist 5" "$SCR"; then
    echo "INCONCLUSIVE: the character is not a 5th-level Alienist, so the key"
    echo "              script has rotted. Nothing was measured."
    grep -m2 "Mage\|Alienist" "$SCR" | head -2
    exit 1
fi
echo "  ok: a Mage 5 / Alienist 5 exists, so the gate and the levels are real"

if grep -q "seems unsettled" "$SCR"; then
    echo "  ok: a creature entering her field is unsettled by it"
else
    echo "FAIL: nothing was unsettled, so Surreal Presence is not on her"
    sed -n '2,3p' "$SCR"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: an Alienist past 3rd level carries the Surreal Presence field"
    echo "      her own prose has always promised"
    exit 0
fi
exit 1
