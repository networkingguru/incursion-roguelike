#!/bin/bash
# Regression check for the Sharp Senses skill bonus, inc-tek.8.3 finding
# PA-03-F18.
#
# The elf's own text promises "a +2 insight bonus to all sensory-based skills
# (Search, Spot, and Listen)" (lib/races.irh:1067-1068) and grants nothing but
# ABILITY(CA_SHARP_SENSES,2) (lib/races.irh:952). The sentinel makes the same
# promise for +1 (lib/prestige.irh:2434-2435). Character::SkillLevel gave the
# bonus to Spot and Listen (src/Create.cpp) but keyed Search off a different
# ability, CA_STONEWORK_SENSE, so Search never received it.
#
# This runs the game and reads the character sheet, because the sheet prints
# each skill's terms one by one -- "+2 inherent" is the term under test -- and
# src/Sheet.cpp:904 gets them by calling SkillLevel itself. The sheet is
# therefore a true oracle for the function under test.
#
# Usage: tools/check_sharp_senses.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/elf-search.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SHEET="$RUN/logs/sheet.txt"

# A session that measured nothing must never read as a pass -- that mistake is
# inc-loa.3.
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi

if [ ! -f "$SHEET" ]; then
    echo "FAIL: the sheet was never written to $SHEET"
    exit 1
fi

# Guard first, assertion second. If the key script stops producing an elf --
# because a race was added to lib/ and the menu letters moved -- the assertion
# below would pass or fail for the wrong reason.
if ! grep -q "Race   Elf" "$SHEET"; then
    echo "FAIL: the character is not an elf, so the key script has rotted."
    grep -m1 "Race " "$SHEET"
    exit 1
fi

fail=0

# The assertion. All three sensory skills, not just the one that was broken:
# the fix must not have moved the bonus from Spot and Listen onto Search.
for skill in Searching Spot Listen; do
    line="$(grep -m1 "^  $skill " "$SHEET")"
    if [ -z "$line" ]; then
        echo "FAIL: no $skill line on the sheet"
        fail=1
        continue
    fi
    if echo "$line" | grep -q "+2 inherent"; then
        echo "  ok: $line"
    else
        echo "FAIL: $skill carries no +2 inherent bonus from Sharp Senses"
        echo "      $line"
        fail=1
    fi
done

if [ "$fail" = 0 ]; then
    echo "PASS: an elf's Searching, Spot and Listen each carry Sharp Senses' +2"
    exit 0
fi
exit 1
