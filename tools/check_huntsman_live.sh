#!/bin/bash
# Regression check for the three Twilight Huntsman fixes of bd inc-tek.8.3:
# PA-03-F1 (the class never gained access to its own spell list), PA-03-F2
# (its Smite Law was coded as Smite Good) and PA-03-F19 (its Tracking
# advanced about four times as fast as the ranger's it claims to stack with).
#
# All three are grants in the class's Grants: block, so nothing can see them
# until a character holds the class. tools/keys/prestige-huntsman.keys builds
# one -- Elf Ranger 3 / Rogue 3 / Twilight Huntsman 5 -- and this script reads
# the three oracles off him.
#
# THE ORACLES, and why each is fair:
#   Smite    src/Sheet.cpp:501-509 prints the CA_SMITE stati's Val through
#            MTypeNames, so the sheet names the very constant the grant sets.
#   Tracking src/Sheet.cpp:719 prints AbilityLevel(CA_TRACKING) * 10 as feet,
#            so the number is the ability level the grant built, times ten.
#   Spells   src/Create.cpp:4190-4198 builds the castable list by walking the
#            SPELL_ACCESS stati and reading each granting resource's
#            SPELL_LIST. The [L]earn Spells menu is that list.
#
# WHAT THE NUMBERS MEAN. On a module compiled from the pre-fix lib/prestige.irh
# the same character reads "Smite Good Creatures" and "Tracking (520 feet)",
# and his spell menu holds 26 ranger spells and none of the huntsman's own.
# 520 is the old +10-per-level grant: huntsman 40 plus ranger 12, times ten.
# 280 is the corrected grant with each class still counting only itself.
# 220 is the corrected grant with the two classes stacked, which is what the
# huntsman's description asks for. See bd inc-0rw.
#
# Usage: tools/check_huntsman_live.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=7
KEYS=tools/keys/prestige-huntsman.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
DUMP="$RUN/logs/hunt.txt"
LEARN="$(ls "$RUN"/logs/screens/*learn.txt 2>/dev/null | head -1)"

if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi

if [ ! -f "$DUMP" ]; then
    echo "FAIL: the character dump was never written to $DUMP"
    echo "$OUT" | tail -12
    exit 1
fi

# Guard first, assertions second. If the key script stops producing a
# 5th-level huntsman -- because a prestige class was added to lib/ and the
# menu moved, or because an entry requirement changed -- every assertion
# below would fail for the wrong reason, and a rotted script must not read as
# a broken game.
if ! grep -q "Twilight Huntsman 5" "$DUMP"; then
    echo "INCONCLUSIVE: the character is not a 5th-level Twilight Huntsman,"
    echo "              so the key script has rotted. Nothing was measured."
    grep -m3 "Ranger\|Rogue\|Huntsman" "$DUMP" | head -3
    exit 1
fi

fail=0

# PA-03-F2. MA_GOOD became MA_LAWFUL.
if grep -q "Smite Lawful Creatures" "$DUMP"; then
    echo "  ok: Smite Lawful Creatures"
else
    echo "FAIL: the huntsman does not smite Lawful creatures"
    grep -m1 "Smite" "$DUMP" || echo "      (no Smite line at all)"
    fail=1
fi
if grep -q "Smite Good Creatures" "$DUMP"; then
    echo "FAIL: the huntsman still smites Good creatures"
    fail=1
fi

# PA-03-F19, and the stacking rule of bd inc-0rw on top of it. The grant now
# copies the ranger's own two-line shape, so the huntsman's share is 10 + 2
# per level after the 2nd rather than 10 per level. That alone gave this
# character 280 feet: ranger 12 plus huntsman 16, times ten.
#
# 220 is what Character::CorrectStackedAbilities (src/Create.cpp) then takes
# off. Both classes open with a one-off +10 at their own 2nd level
# (lib/classes.irh:2127, lib/prestige.irh:2954), and the huntsman's
# description stacks his levels with the ranger's, so the character is owed
# that opening bonus once and not twice. Eight levels at 2 a level is 16,
# plus the 10, is 22.
if grep -q "Tracking (220 feet)" "$DUMP"; then
    echo "  ok: Tracking (220 feet)"
else
    echo "FAIL: the tracking range is not the once-stacked 220 feet"
    grep -m1 "Tracking" "$DUMP" || echo "      (no Tracking line at all)"
    fail=1
fi

# PA-03-F1. Four spells that appear on the huntsman's own list and on no
# list a Ranger 3 / Rogue 3 could otherwise reach. Bane, Faerie Fire,
# Malignance and Enthrall are all in lib/prestige.irh's 1st-level block.
if [ -z "$LEARN" ]; then
    echo "FAIL: the [L]earn Spells screen was never dumped"
    fail=1
else
    for spell in Bane "Faerie Fire" Malignance Enthrall; do
        if grep -q "$spell" "$LEARN"; then
            echo "  ok: the spell menu offers $spell"
        else
            echo "FAIL: the spell menu does not offer $spell"
            fail=1
        fi
    done
    # The sharpest single line. Longstrider, Slow Poison and True Strike are
    # on the ranger's list AND the huntsman's, so once the huntsman grants
    # access they are offered twice, one entry per source. A duplicate
    # labelled (Divine) cannot come from anywhere but the new grant.
    if grep -q "Longstrider (Divine" "$LEARN"; then
        echo "  ok: Longstrider is offered a second time, as (Divine)"
    else
        echo "FAIL: no (Divine) copy of Longstrider, so the huntsman's own"
        echo "      spell list is still not being read"
        fail=1
    fi
fi

if [ "$fail" = 0 ]; then
    echo "PASS: a live Twilight Huntsman smites Law, tracks at the ranger's"
    echo "      pace once and not twice, and is offered his own spell list"
    exit 0
fi
exit 1
