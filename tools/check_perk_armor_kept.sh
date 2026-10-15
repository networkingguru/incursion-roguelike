#!/bin/bash
# gate: live
# Does a starting-perk armour reach the inventory? (bd inc-kzp1)
#
# THE DEFECT. A human Paladin who picks seed 21's attribute set [e] has the
# perk "uncursed plate mail +2". GrantPerks wears it. Then ArrangeStartingKit
# rule 1 (src/Create.cpp) finds the kit's field plate armour a better "wear"
# candidate and calls KitToSlot(SL_ARMOUR). Character::Wield (src/Inv.cpp)
# overwrites Inv[SL_ARMOUR] and does not take the old armour off, and
# Character::GetInv walks Inv[] slots, so the plate mail is orphaned: still
# owned, not in any slot or container, absent from inventory and save.
#
# THE ORACLE is logs/charprobe.txt (INCURSION_CHAR_PROBE=1, written at the
# key script's Save and Continue): every "Starting Item: uncursed <name>"
# line in the Starting Perks journal must appear as a line of Inventory.
#
# Usage: tools/check_perk_armor_kept.sh
#   0 every perk item is in the inventory
#   1 a perk item is missing from the inventory
#   2 could not measure (no build, run failed, no Starting Perks section)
. "$(dirname "$0")/check_lib.sh"

OPTIONS=tools/fixtures/options-2026-08-22.dat
[ -x ./incursion-headless ] || _check_die 2 "incursion-headless is not built." \
    "Run: BACKEND=posix ./build_macos.sh"

RUN="$PWD/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-perk-armor"
INCURSION_OPTIONS="$OPTIONS" INCURSION_CHAR_PROBE=1 INCURSION_RUN_DIR="$RUN" \
    tools/headless.sh tools/keys/kzp1-perk-armor.keys 21 > "$RUN.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] || _check_die 2 "headless.sh exited $rc (see $RUN.out)."
PROBE="$RUN/logs/charprobe.txt"
[ -f "$PROBE" ] || _check_die 2 "no charprobe.txt under $RUN."

PERKS="$(sed -n '/Starting Perks:/,/^$/p' "$PROBE" | grep 'Starting Item:' |
    sed -e 's/.*Starting Item: *//' -e 's/\.$//' -e 's/^uncursed //')"
[ -n "$PERKS" ] || _check_die 2 "no Starting Item perk in the journal ($PROBE)."
INV="$(sed -n '/^Inventory:/,/^$/p' "$PROBE")"

MISSING=0
while IFS= read -r perk; do
    if printf '%s\n' "$INV" | grep -qF -- "$perk"; then
        echo "kept:    $perk"
    else
        echo "MISSING: $perk (listed under Starting Perks, absent from Inventory)"
        MISSING=1
    fi
done <<< "$PERKS"
exit "$MISSING"
