#!/bin/bash
# Regression check for the Rod of Lordly Might's flaming-long-sword plus,
# inc-tek.8.8. Both labels promise +1, but the transform used to grant +2.
#
# A pinned running game wields the rod, transforms it, and dumps the sidebar.
# The oracle reads the wielder's real Hit and Dmg lines, not lib/m_items.irh.
# On this character the bad +2 form reads Hit:9 / Dmg:1d8+6; the promised +1
# form is exactly one lower on each reading, Hit:8 / Dmg:1d8+5.
#
# Usage: tools/check_rod_longsword_plus.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/rod-longsword-plus.keys
SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

OUT="$(INCURSION_OPTIONS=tools/gates/Options.Dat \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"

if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: the run never entered a map, so it measured nothing"
    exit 2
fi
if echo "$OUT" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script did not find an expected screen"
    echo "$OUT"
    exit 2
fi

DUMP="$RUN/logs/screens/0002-0002-longsword.txt"
[ -f "$DUMP" ] || {
    echo "INCONCLUSIVE: no transformed-weapon dump at $DUMP"
    exit 2
}

HIT="$(sed -n 's/.*|Hit:\([-0-9]*\).*/\1/p' "$DUMP" | head -1)"
DMG="$(sed -n 's/.*|Dmg:\([^ ]*\).*/\1/p' "$DUMP" | head -1)"

echo "Rod flaming long sword: Hit:$HIT Dmg:$DMG"

if [ "$HIT" != 8 ] || [ "$DMG" != "1d8+5" ]; then
    echo "FAIL: expected Hit:8 Dmg:1d8+5 for the labeled +1 flaming long sword"
    echo "      dump: $DUMP"
    exit 1
fi

echo "PASS: the Rod of Lordly Might's flaming long sword grants +1"
