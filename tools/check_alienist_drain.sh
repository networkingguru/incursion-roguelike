#!/bin/bash
# Regression check for the Alienist's Outer Pathways mana price, bd inc-tek.22,
# finding PA-03-F26 of bd inc-tek.8.3.
#
# THE DEFECT. The class description says each pseudonatural summoning "drains
# [Summoned Creature's CR x 2] mana, and this mana does not regenerate"
# (lib/prestige.irh:290-292). ALIENIST_CLAUSE (lib/defines.irh) charged nothing.
#
# THE ORACLE is the status line's Mana figure, read twice: once just after the
# cast and once after ten searches have passed about fifteen thousand turns.
# Spent mana regenerates and held mana does not (inc/Creature.h:145-146), so a
# shortfall that survives the wait is held mana and nothing else. Searching is
# used rather than resting on purpose: a completed rest zeroes held mana
# outright (src/Player.cpp:2186-2188).
#
# The character is an Alienist 5 casting Monster Summoning III, which calls a
# CR 3 creature, so the price is 6 and the maximum is 720.
#
# Usage: tools/check_alienist_drain.sh     (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/prestige-pseudonatural.keys
SEED=1

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCREENS="$RUN/logs/screens"

if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi

mana() {   # mana <dump label> -> current mana
    local f="$SCREENS/$1"
    [ -f "$f" ] || { echo ""; return; }
    grep -o "Mana:[0-9]*" "$f" | head -1 | cut -d: -f2
}

BEFORE="$(mana 0001-before.txt)"
AFTER="$(mana 0002-after.txt)"
SETTLED="$(mana 0003-settled.txt)"

if [ -z "$BEFORE" ] || [ -z "$AFTER" ] || [ -z "$SETTLED" ]; then
    echo "FAIL: could not read all three mana figures from $SCREENS"
    exit 1
fi

# The summon must actually have happened, or the whole run proves nothing.
if ! grep -q "appears!" "$SCREENS/0002-after.txt"; then
    echo "FAIL: no creature was summoned, so nothing could be converted"
    echo "      dump: $SCREENS/0002-after.txt"
    exit 1
fi

DRAIN=$((BEFORE - SETTLED))

if [ "$DRAIN" -eq 0 ]; then
    echo "FAIL: the pseudonatural summoning cost nothing. Mana was $BEFORE"
    echo "      before the cast and is still $SETTLED after it."
    echo "      run: $RUN"
    exit 1
fi

if [ "$DRAIN" -ne 6 ]; then
    echo "FAIL: expected a held drain of 6 (CR 3 x 2), measured $DRAIN"
    echo "      before $BEFORE, after cast $AFTER, settled $SETTLED"
    echo "      run: $RUN"
    exit 1
fi

echo "PASS: the summoning held 6 mana (CR 3 x 2) and it did not come back."
echo "      before $BEFORE, after cast $AFTER, settled $SETTLED (max 720)"
echo "      run: $RUN"
exit 0
