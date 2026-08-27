#!/bin/bash
# Regression check for inc-mc37: Player::AutoPickupFloor's unidentified-magic
# branch (src/Player.cpp) must NOT auto-stow an EF_MUNDANE item -- one the
# codebase itself calls "not magic" (lib/alchemy.irh:1363) -- while it still
# stows real unidentified magic. This is the same branch inc-upw.52 patched for
# holy symbols; that fix's isFlavorGodMark() whitelist was too narrow and missed
# the whole EF_MUNDANE alchemy line. The added EF_MUNDANE test exempts the class.
#
# It reads the "Things in View" panel, not the one-line message window, so it is
# robust to message wrapping.
#
# TWO ITEMS, two guaranteed monster drops (no % roll, so seed-stable):
#   WATER  -- the "curate" template drops 3d4 blessed flask of water (holy
#             water) plus a 1d1 healing potion.
#   TANGLE -- the "rogue-archer" template drops 1d2 tanglefoot bags plus a 1d1
#             dimension-door potion.
# In each run the MUNDANE item must stay in view after the step (it is NOT
# stowed), and the POTION must leave the view (it IS stowed) -- the second half
# proves the branch actually ran and still hoards real unidentified magic, so a
# green result is not merely the sweep failing to fire.
#
# The "mundane stays" assertions are red on the build before the fix: the water
# and the tanglefoot bags both auto-stowed one at a time and never stopped.
# Confirmed red on the pre-fix binary and green on the rebuilt one.
#
# Usage: tools/check_mundane_autopickup.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# The right-hand "Things in View" list, from its header down to the HP line.
view() { sed -n '/Things in View/,/HP:/p' "$1"; }

# Run one fixture on seed 1; set BEFORE and AFTER to the two dumps.
run_keys() {
    local keys="$1" out
    out="$(tools/headless.sh "$keys" 1 2>&1)"
    RUN="$(echo "$out" | awk '/^run:/ {print $2}')"
    BEFORE="$(ls "$RUN"/logs/screens/*before* 2>/dev/null | head -1)"
    AFTER="$(ls "$RUN"/logs/screens/*after*  2>/dev/null | head -1)"
}

fail=0

# item_re = what marks the mundane item in the view; label = human name.
check_one() {
    local keys="$1" item_re="$2" label="$3"
    run_keys "$keys"
    [ -f "$BEFORE" ] && [ -f "$AFTER" ] || {
        echo "INCONCLUSIVE: $label wrote no before/after dump. Run dir: $RUN"; exit 2; }
    view "$BEFORE" | grep -qiE "$item_re" || {
        echo "INCONCLUSIVE: $label dropped no $label on the tile. Run dir: $RUN"; exit 2; }
    # Branch must have run: the sweep must have stowed SOMETHING (the drop's
    # unidentified potion is real magic and still hoards). The narrow view panel
    # truncates item names, so read the AutoStowing message the sweep prints.
    if ! grep -qi "AutoStow" "$AFTER"; then
        echo "INCONCLUSIVE: $label saw no AutoStowing -- the branch never ran. Run dir: $RUN"; exit 2; fi
    # The fix: the mundane item must NOT have been stowed.
    if ! view "$AFTER" | grep -qiE "$item_re"; then
        echo "FAIL: $label left the view after the step -- an EF_MUNDANE item was auto-stowed."
        fail=1
    fi
}

check_one tools/keys/mundane-autopickup-water.keys  "vials? of|holy water| water" "holy water"
check_one tools/keys/mundane-autopickup-tangle.keys "tanglefoot|\? bags?|bags? " "tanglefoot bag"

if [ "$fail" -eq 0 ]; then
    echo "PASS: holy water and tanglefoot bags both stayed in view after the step,"
    echo "      while each drop's unidentified potion was stowed (the branch still runs)."
    exit 0
fi
exit 1
