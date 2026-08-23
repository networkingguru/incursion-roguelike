#!/bin/bash
# Regression check for the kinds that identification never taught, bd inc-bj4z.
#
# THE DEFECT. Item::MakeKnown (src/Item.cpp) recorded that a KIND had been
# identified -- EFFMEM(eID,player)->Known, which is what makes the next item of
# that kind arrive already named -- only for a hand-written list of item types:
# scroll, wand, ring, gauntlets, girdle, crown, helmet, tome, cloak, boots, rod,
# staff, and potion through PKnown. That list had drifted from the Flavored
# column of DungeonItems (src/Tables.cpp), which is what actually decides
# whether a kind has a flavour name to learn. Flavoured and missing: amulets,
# bracers, lenses, mushrooms and horns. In the list and not flavoured:
# tomes and crowns.
#
# So Brian, wearing a fully identified Periapt of Wisdom, had to identify the
# next Periapt of Wisdom he found, and the one after that.
#
# It is upstream's: the list is byte-identical in cea33d8, Julian's own 0.6.9H3
# source, and behaves the same on Win32 with the original typedefs.
#
# THE ORACLE is the Inventory Manager's In-the-Air line, which names the item
# the wizard menu's "Acquire Unknown Item" has just handed over unidentified.
# An unlearned kind reads by its flavour, a learned one by its name:
#
#                       amulet (was broken)      ring (the control)
#   first, unknown      ? pearl amulet           ? electrum ring
#   after identifying   ? pearl amulet   BEFORE  ? Ring of Good Fortune
#                       ? Periapt of Wisdom  AFTER
#
# The ring is in the run for a reason. It is the kind that always worked, so if
# the ring line does not change across the identify, the run has not measured
# the bug at all -- the identify never happened, or the browser handed over the
# wrong item -- and this script says INCONCLUSIVE rather than FAIL. Sending
# somebody hunting a regression that a dead session invented is inc-loa.3.
#
# The flavour words ("pearl", "electrum") are NOT asserted. Flavours are dealt
# per game from the pool in lib/, so pinning them would make this script fail
# on a content change that is none of its business. What it asserts is only
# whether the line reads a flavour or a name.
#
# Usage: tools/check_item_type_id.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/amulet-idtype.keys
SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# Pinned settings, not the live Options.Dat, which Brian's own play rewrites.
OUT="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"

if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: the run never entered a map, so it measured nothing."
    echo "$OUT" | sed 's/^/              /'
    exit 2
fi

# Read the item name off one screen's In-the-Air line. The game's colour bytes
# are dropped, but NOT the newlines -- strip those and the whole screen becomes
# one line and every match runs to the end of it. The name ends at the first run
# of two spaces, which is the gap before the weight column.
airline() {
    local f="$RUN/logs/screens/$1"
    [ -f "$f" ] || return 1
    LC_ALL=C grep -a -m1 "In the Air" "$f" |
        LC_ALL=C tr -cd '\40-\176\n' |
        sed -e "s/.*'In the Air'[[:space:]]*:[[:space:]]*//" \
            -e 's/[[:space:]][[:space:]].*$//' \
            -e 's/[[:space:]]*$//'
}

A1="$(airline 0002-amulet-1-in-air.txt)" || true
R1="$(airline 0003-ring-1-in-air.txt)"   || true
A2="$(airline 0004-amulet-2-in-air.txt)" || true
R2="$(airline 0005-ring-2-in-air.txt)"   || true

for pair in "amulet-1:$A1" "ring-1:$R1" "amulet-2:$A2" "ring-2:$R2"; do
    if [ -z "${pair#*:}" ]; then
        echo "INCONCLUSIVE: no In-the-Air line for ${pair%%:*}. The wizard menu or"
        echo "              the acquisition browser did not give the item over."
        echo "              Screens: $RUN/logs/screens"
        exit 2
    fi
done

echo "in the air:"
echo "  first amulet:  $A1"
echo "  first ring:    $R1"
echo "  second amulet: $A2"
echo "  second ring:   $R2"
echo

# The first of each pair must be UNknown, or there was nothing to learn.
case "$A1" in
    *"Periapt of Wisdom"*)
        echo "INCONCLUSIVE: the first amulet arrived already named, so this run"
        echo "              never had an unidentified kind to learn."
        exit 2 ;;
esac
case "$R1" in
    *"Ring of"*)
        echo "INCONCLUSIVE: the first ring arrived already named, so the control"
        echo "              proves nothing about whether the identify ran."
        exit 2 ;;
esac

# The control: the kind that always worked must still work.
case "$R2" in
    *"Ring of"*) ;;
    *)
        echo "INCONCLUSIVE: the second ring still reads by flavour ($R2), so the"
        echo "              identify did not happen or did not reach the pack."
        echo "              Nothing can be concluded about the amulet."
        echo "              Screens: $RUN/logs/screens"
        exit 2 ;;
esac

# The assertion.
case "$A2" in
    *"Periapt of Wisdom"*)
        echo "PASS: identifying one Periapt of Wisdom taught the kind -- the next"
        echo "      one arrives named ($A2), the same as the ring control does."
        echo "      seed $SEED, $RUN/logs/screens"
        exit 0 ;;
esac

echo "FAIL: the second Periapt of Wisdom still reads by flavour ($A2) after an"
echo "      identical one was identified, while the ring control learned its"
echo "      kind in the same run. Item::MakeKnown (src/Item.cpp) is deciding by"
echo "      item type again instead of by whether the effect carries a flavour."
echo "      Screens: $RUN/logs/screens"
exit 1
