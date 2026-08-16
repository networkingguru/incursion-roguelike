#!/bin/bash
# Regression check for the racial-feat bug, inc-2a0.
#
# A Race resource has no feat field of its own, so a racial feat can only be
# written on the race's Monster: template. Character::HasFeat did not read that
# template, so for years every player silently lost those feats: Dragonkin lost
# Mantis Leap, dwarves lost Loadbearer, halflings lost Slipaway, grey dwarves
# lost three. Monsters were never affected. See src/Create.cpp, HasFeat.
#
# This runs the game and reads the character sheet, because that is the screen
# Brian looked at when he noticed. src/Sheet.cpp:787-788 builds the Feats block
# with HasFeat(), so the sheet is a true oracle for the function under test.
#
# Usage: tools/check_race_feats.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/dragonkin-sheet.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCREENS="$RUN/logs/screens"

# The harness exits 5 when the run never entered a map. A session that measured
# nothing must never be read as a pass -- that mistake is inc-loa.3.
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi

if [ ! -d "$SCREENS" ]; then
    echo "FAIL: no screen dumps at $SCREENS"
    exit 1
fi

# Guard first, assertion second. If the key script no longer produces a
# Dragonkin -- because a race was added to lib/ and the menu letters moved --
# then the run is inconclusive, NOT a rules regression. Reporting it as the
# latter would send somebody hunting a bug that is not there.
if ! grep -qh "Race   Dragonkin" "$SCREENS"/*.txt; then
    echo "INCONCLUSIVE: $KEYS did not produce a Dragonkin."
    echo "  The race or subrace menu letters have moved. Fix the key script."
    echo "  Screens: $SCREENS"
    exit 1
fi

# The assertion that bites.
if grep -qh "Mantis Leap" "$SCREENS"/*.txt; then
    echo "PASS: a Dragonkin has Mantis Leap from its species template"
    exit 0
fi

echo "FAIL: Dragonkin character sheet has no Mantis Leap."
echo "  The feat is on the template at lib/subraces.irh:731, so"
echo "  Character::HasFeat has stopped reading TMON(tmID). See inc-2a0."
echo "  Screens: $SCREENS"
exit 1
