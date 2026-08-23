#!/bin/bash
# Regression check for the Earthsinger's Geomancy payout, bd inc-tek.21,
# finding PA-03-F25 of bd inc-tek.8.3.
#
# THE DEFECT. Geomancy turns fatigue into mana. The class page says 5d12
# (lib/prestige.irh:1543) and the effect's own description repeats 5d12, while
# the value was pval: 5d12+12 -- the whole line copied from the *Mana* potion
# (lib/m_items.irh:1192), whose own description does state the +12.
#
# THE ORACLE is the Spell Manager's "Power & Metamagic" column, which prints
# the effect's pval beside the ability. So the number the player reads and the
# number the engine rolls are one field, and this check needs no statistics
# over dice.
#
# Usage: tools/check_geomancy.sh          (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/prestige-geomancy.keys
SEED=1

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
DUMP="$RUN/logs/screens/0001-spellmanager.txt"

# A session that measured nothing must never read as a pass -- inc-loa.3.
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi
if [ ! -f "$DUMP" ]; then
    echo "FAIL: no Spell Manager dump at $DUMP"
    exit 1
fi

ROW="$(grep "Geomancy" "$DUMP")"
if [ -z "$ROW" ]; then
    echo "FAIL: the Spell Manager did not list Geomancy at all"
    echo "      dump: $DUMP"
    exit 1
fi

if echo "$ROW" | grep -q "5d12+12"; then
    echo "FAIL: Geomancy still pays 5d12+12, which neither of its two"
    echo "      descriptions promises."
    echo "      row:  $(echo "$ROW" | tr -s ' ')"
    echo "      dump: $DUMP"
    exit 1
fi

if ! echo "$ROW" | grep -q "5d12"; then
    echo "FAIL: Geomancy's power column does not read 5d12"
    echo "      row:  $(echo "$ROW" | tr -s ' ')"
    echo "      dump: $DUMP"
    exit 1
fi

echo "PASS: Geomancy pays 5d12, the value both of its descriptions promise."
echo "      row:  $(echo "$ROW" | tr -s ' ')"
echo "      dump: $DUMP"
exit 0
