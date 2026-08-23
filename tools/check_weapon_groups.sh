#!/bin/bash
# Regression check for the weapon-group name table, bd inc-tek.15.
#
# WeaponGroupNames[] (src/Tables.cpp) is the only thing that turns a creature's
# Proficiencies bits into words. Three sites print a proficiency list, and each
# guards every bit with LookupOnly(WeaponGroupNames, 1L << i): the character
# sheet (src/Sheet.cpp:855), the class help page (src/Help.cpp:101) and the
# per-group weapon listing (src/Help.cpp:1240). A bit with no row in the table
# is therefore dropped in silence -- no assert, no error line, just a shorter
# sentence. WG_LIGHT was missing that row, so no class ever said it was
# proficient with light weapons; WG_CROSSBOWS had been missing for the same
# reason and was added on 2026-08-20.
#
# Two checks, in the order that finds the fault fastest.
#
#   1. STATIC. Every WG_ bit declared in inc/Defines.h has a row in the table.
#      This needs no game, runs in a second, and catches the NEXT missing row
#      rather than only the one already fixed.
#   2. OBSERVED. A real session builds an elf bard and dumps his character
#      sheet, and the Proficiencies line must name Light Weapons. The bard
#      grants WG_LIGHT at lib/classes.irh:444, and his own prose promises
#      "light weapons" at lib/classes.irh:289. The sheet is a true oracle,
#      because src/Sheet.cpp builds that line by reading the table under test.
#
# Usage: tools/check_weapon_groups.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/bard-profs.keys
fail=0

# --- 1. static: declaration and table must hold the same set of bits --------
#
# The table's rows are read from the initialiser only. The upstream: marker
# above it names WG_LIGHT and WG_CROSSBOWS in prose, and reading those as rows
# would make this check pass on a table that has neither.
DECLARED="$(grep -oE '^#define +WG_[A-Z]+' inc/Defines.h | awk '{print $2}' | sort -u)"
LISTED="$(awk '/^TextVal WeaponGroupNames\[\] = \{/{t=1;next} t&&/\{ *0, *NULL *\}/{t=0} t' \
          src/Tables.cpp | grep -oE 'WG_[A-Z]+' | sort -u)"

if [ -z "$DECLARED" ] || [ -z "$LISTED" ]; then
    echo "FAIL: read no WG_ bits at all (declared: $(echo "$DECLARED" | grep -c .), \
listed: $(echo "$LISTED" | grep -c .)). The check found nothing to check, which"
    echo "      is not a pass -- the table or the #define block has been renamed."
    exit 1
fi

MISSING="$(comm -23 <(echo "$DECLARED") <(echo "$LISTED"))"
EXTRA="$(comm -13 <(echo "$DECLARED") <(echo "$LISTED"))"

if [ -n "$MISSING" ]; then
    echo "FAIL: these WG_ bits have no row in WeaponGroupNames[], so every"
    echo "      proficiency list drops them without saying so:"
    echo "$MISSING" | sed 's/^/        /'
    fail=1
fi
if [ -n "$EXTRA" ]; then
    echo "FAIL: WeaponGroupNames[] names bits that inc/Defines.h does not declare:"
    echo "$EXTRA" | sed 's/^/        /'
    fail=1
fi
if [ -z "$MISSING" ] && [ -z "$EXTRA" ]; then
    echo "  ok: all $(echo "$DECLARED" | grep -c .) WG_ bits have a name in WeaponGroupNames[]"
fi

# --- 2. observed: the sheet must print the name --------------------------
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

# Guard first, assertion second. If the key script stops producing a bard --
# because a class was added to lib/ and a menu moved -- the assertion below
# would pass or fail for the wrong reason. The bard is the character under
# test precisely because he carries WG_LIGHT.
if ! grep -q "^Class  *Bard 1" "$SHEET"; then
    echo "FAIL: the character is not a first-level bard, so the key script has rotted."
    grep -m1 "^Class" "$SHEET"
    exit 1
fi

LINE="$(grep -m1 "^Proficiencies" "$SHEET")"
if [ -z "$LINE" ]; then
    echo "FAIL: the sheet carries no Proficiencies line at all"
    exit 1
fi

# The assertion. All five of the bard's groups, not only the one that was
# broken: the fix must add a name without displacing any other.
for group in "Simple Weapons" "Short Blades" "Archery" "Daggers" "Light Weapons"; do
    if echo "$LINE" | grep -q "$group"; then
        echo "  ok: the sheet names $group"
    else
        echo "FAIL: the bard's proficiency list does not name $group"
        echo "      $LINE"
        fail=1
    fi
done

if [ "$fail" = 0 ]; then
    echo "PASS: every WG_ bit has a name, and an elf bard's sheet prints all five of his"
    exit 0
fi
exit 1
