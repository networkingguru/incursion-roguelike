#!/bin/bash
# gate: live
# Does a better armour put on at creation leave the displaced armour in the
# inventory? (bd inc-kzp1)
#
# THE DEFECT. ArrangeStartingKit (src/Create.cpp) wears a better armour in the
# armour slot. Character::Wield overwrites Inv[SL_ARMOUR] and does not take the
# old armour off, so the old armour was orphaned: owned, in no slot or container,
# absent from inventory and save. The fix packs it: KitToPack(p,old).
#
# SCENARIO. A human Paladin (Point Buy, no roll, no perks) gets the kit's field
# plate armour (total 30) plus a granted full plate armour (total 36). The
# arranging step wears the full plate; the field plate is the displaced armour.
#
# THE ORACLE is INCURSION_KIT_PROBE: the KIT_ITEM lines in the run's logs.
#   full plate armour must sit in the armour slot (sl=9), else no swap happened.
#   field plate armour must appear on some KIT_ITEM line (the pack or a slot).
#
# fact: settings -- the pinned options file tools/fixtures/options-2026-08-22.dat
# fact: attribute scores -- Point Buy in tools/keys/kit-paladin.keys (no roll)
# fact: perks -- none under Point Buy
# fact: the kit's field plate armour -- fixed by the named class (Paladin) and race (Human)
# fact: the second, better armour -- INCURSION_KIT_GRANT "full plate armour" (armour total 36 vs 30, lib/weapons.irh)
# fact: monsters and turns -- KIT_PROBE writes at creation, before any turn
#
# Usage: tools/check_perk_armor_kept.sh [seed]   (default seed 1; the sweep overrides it)
#   0 PASS: the displaced armour is kept
#   1 FAIL: the displaced armour is missing
#   2 could not measure (no build, run failed, no KIT_ITEM lines, no swap)
. "$(dirname "$0")/check_lib.sh"

OPTIONS=tools/fixtures/options-2026-08-22.dat
[ -x ./incursion-headless ] || _check_die 2 "incursion-headless is not built." \
    "Run: BACKEND=posix ./build_macos.sh"

RUN="$PWD/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-perk-armor"
INCURSION_OPTIONS="$OPTIONS" INCURSION_KIT_PROBE=1 \
    INCURSION_KIT_GRANT="full plate armour" INCURSION_RUN_DIR="$RUN" \
    tools/headless.sh tools/keys/kit-paladin.keys "${1:-1}" > "$RUN.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] || _check_die 2 "headless.sh exited $rc (see $RUN.out)."

ITEMS="$(grep -rh 'KIT_ITEM' "$RUN/logs/" 2>/dev/null)"
[ -n "$ITEMS" ] || _check_die 2 "no KIT_ITEM line under $RUN/logs/."
printf '%s\n' "$ITEMS" | grep 'name="full plate armour"' | grep -q 'sl=9 slot=Armour' ||
    _check_die 2 "full plate armour is not in the armour slot; no swap happened ($RUN)."

if printf '%s\n' "$ITEMS" | grep -q 'name="field plate armour"'; then
    printf '%s\n' "$ITEMS" | grep 'plate armour' | sed 's/^/kept:    /'
    echo "PASS: the displaced field plate armour is still in the inventory."
    exit 0
fi
echo "MISSING: field plate armour (displaced by full plate armour, absent from every KIT_ITEM line)"
echo "FAIL: the displaced armour was lost ($RUN)."
exit 1
