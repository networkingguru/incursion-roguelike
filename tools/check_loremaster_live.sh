#!/bin/bash
# Regression check for bd inc-tek.8.3 finding PA-03-F10: the Loremaster's
# "Bibliographic Insight" had no implementation of any kind.
#
# The class's level table lists the ability at 5th level and its prose
# promises "an extra +1d2 attribute points from any tome they read"
# (lib/prestige.irh:2052-2053). The Grants block jumped from 3rd level to
# 6th, the EV_ADVANCE handler branched only on levels 2, 4 and 8, and
# "Bibliographic" appeared nowhere in lib/ except the table row.
#
# THE FIX cannot live in the class. The attribute gain happens inside each
# tome's own EV_MAGIC_HIT handler, which calls GainInherentBonus with the
# tome's plus; a grant on the class cannot reach into that. So the bonus is
# added where the roll is consumed, in all seven tomes (lib/m_items.irh).
#
# THE ORACLE is the character sheet's Strength line, which itemises where
# each point came from: "STR: 18/00 [+4/+3] (base 13, +5 inherent)".
# GainInherentBonus is what writes that "+N inherent" term.
#
# THE NUMBERS. tools/keys/prestige-loremaster.keys builds a Mage 5 /
# Loremaster 5 and reads two Manuals of Gainful Exercise whose plus is typed
# in as 1 rather than rolled, so the base gain is exactly 1 apiece.
#   without the ability: +2 inherent, always.
#   with it:             +2 plus 2d2, so +4 to +6.
# Measured on this machine: a module compiled from lib/m_items.irh at
# f5444e9^ gives "base 13, +2 inherent"; the same script on the fixed module
# gives "base 13, +5 inherent".
#
# WHY THE PLUS IS 1. GainInherentBonus caps the total at
# 5 + CA_INHERANT_POTENTIAL (src/Creature.cpp:1950) and a human carries +3 of
# that ability (lib/races.irh:205), so this character saturates at +8. Three
# tomes at plus 2 reach +8 with or without the fix and measure nothing.
#
# Usage: tools/check_loremaster_live.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=5
KEYS=tools/keys/prestige-loremaster.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCR="$RUN/logs/screens/0001-sheet.txt"

if [ ! -f "$SCR" ]; then
    echo "FAIL: the sheet was never dumped -- the character never finished."
    echo "$OUT" | tail -10
    exit 1
fi

# Guard first. If the build stops producing a 5th-level Loremaster -- an
# entry requirement changed, the prestige menu moved -- the assertion below
# would fail for the wrong reason.
if ! grep -q "Loremaster 5" "$SCR"; then
    echo "INCONCLUSIVE: the character is not a 5th-level Loremaster, so the"
    echo "              key script has rotted. Nothing was measured."
    grep -m2 "Class\|Loremaster" "$SCR" | head -2
    exit 1
fi
echo "  ok: a Mage 5 / Loremaster 5 exists, so the gate and the levels are real"

STR="$(grep -m1 "STR:" "$SCR")"
INH="$(echo "$STR" | sed -n 's/.*base 13, +\([0-9]*\) inherent.*/\1/p')"

if [ -z "$INH" ]; then
    echo "FAIL: the Strength line does not name an inherent bonus at all, so"
    echo "      neither tome did anything."
    echo "      $STR"
    exit 1
fi

if [ "$INH" = 2 ]; then
    echo "FAIL: +2 inherent Strength, which is the two tomes' plus and nothing"
    echo "      else. Bibliographic Insight added no points."
    echo "      $STR"
    exit 1
fi

if [ "$INH" -lt 4 ] || [ "$INH" -gt 6 ]; then
    echo "FAIL: +$INH inherent Strength is outside the +4..+6 that two plus-1"
    echo "      tomes and two rolls of 1d2 can produce. Something other than"
    echo "      this ability moved the number."
    echo "      $STR"
    exit 1
fi

echo "  ok: +$INH inherent Strength, against the +2 the tomes alone give"
echo "PASS: a Loremaster of 5th level reads more out of a tome than the tome"
echo "      carries, which is what Bibliographic Insight has always claimed"
exit 0
