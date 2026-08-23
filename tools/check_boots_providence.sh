#!/bin/bash
# Do the Boots of Providence pay their Luck bonus while carried? Bead inc-izuu.
#
# THE DEFECT. The boots' page, and the Ring of Good Fortune's, each open with
# "When carried or worn, this item bestows good luck upon its wielder in the
# form of a magic bonus to his Luck score." Only worn paid. An item's grant is
# thrown from Wield (src/Inv.cpp:396 and 111) and only for a slot
# Item::activeSlot calls active; that function exempted stones from the
# worn-slot rule and nothing else, so a ring or a pair of boots on the belt was
# inert. The wording is not copied from the Luckstone above them: the Luckstone
# says "When carried" and somebody deliberately added "or worn" to these two.
#
# THE ORACLE is the character sheet's attribute line, which prints the score and
# every bonus that built it (src/Sheet.cpp:91-99). The carried boots read
# "LUC: 15/00 [+2/+2]  (base 15)" before the fix and
# "LUC: 18/00 [+4/+3]  (base 15, +3 magic)" after it.
#
# Three more readings keep the fix honest, because "the belt now pays" is the
# easy way to get the first one and is wrong:
#   worn      the same +3 and not +6, so the grant is not applied twice.
#   dropped   back to base, so no bonus outlives the item.
#   control   Boots of the Winterlands, which promise nothing about being
#             carried and carry no EF_CARRIED flag, take the same route and
#             must stay inert on the belt. Their cold resistance appears in the
#             sheet's Resistances block only once they are on the feet.
#
# Usage: tools/check_boots_providence.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# $1 key script, $2 the name this check calls it. Echoes the run directory.
run_session() {
    local out run
    out="$(tools/headless.sh "$1" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q "the key script looked for something"; then
        echo "INCONCLUSIVE: the $2 key script could not find something on" >&2
        echo "              screen. Run: $run" >&2
        exit 2
    fi
    [ -n "$run" ] || { echo "INCONCLUSIVE: no run directory for $2." >&2; exit 2; }
    echo "$run"
}

screen() {
    local f="$1/logs/screens/$2"
    [ -f "$f" ] || { echo "INCONCLUSIVE: no screen dumped at $f" >&2; exit 2; }
    echo "$f"
}

rc=0

### The boots the page makes a promise about.

run="$(run_session tools/keys/boots-providence.keys Providence)"

belt="$(screen "$run" 0001-boots-on-belt.txt)"
carried="$(screen "$run" 0002-sheet-carried.txt)"
feet="$(screen "$run" 0003-boots-worn.txt)"
worn="$(screen "$run" 0004-sheet-worn.txt)"
gone="$(screen "$run" 0005-boots-dropped.txt)"
dropped="$(screen "$run" 0006-sheet-dropped.txt)"

# The acquisition list is walked by cursor, not by menu letter, so read the
# boots' own name and their own slot back before believing any sheet.
grep -q "On Belt      :Boots +3 of Providence" "$belt" || {
    echo "INCONCLUSIVE: no Boots +3 of Providence reached a belt slot, so the"
    echo "              session measured nothing. Screen: $belt"
    exit 2
}
grep -q "Boots        :Boots +3 of Providence" "$feet" || {
    echo "INCONCLUSIVE: the boots never reached the feet, so the worn reading"
    echo "              is not a reading of these boots. Screen: $feet"
    exit 2
}
grep -q "Boots        :Empty" "$gone" || {
    echo "INCONCLUSIVE: the boots never left the feet. Screen: $gone"
    exit 2
}

if ! grep -q "LUC: 18/00 .*(base 15, +3 magic)" "$carried"; then
    echo "FAIL: the Boots of Providence pay nothing while carried, and their"
    echo "      own page says they pay 'when carried or worn'."
    echo "      Screen: $carried"
    rc=1
fi
if ! grep -q "LUC: 18/00 .*(base 15, +3 magic)" "$worn"; then
    echo "FAIL: the boots read wrong on the feet. A +3 pair must give +3, once."
    echo "      Screen: $worn"
    rc=1
fi
if ! grep -q "LUC: 15/00 .*(base 15)" "$dropped"; then
    echo "FAIL: the Luck bonus outlived the boots -- it is still there after"
    echo "      they were dropped."
    echo "      Screen: $dropped"
    rc=1
fi

### The control, which must NOT have gained anything.

crun="$(run_session tools/keys/boots-winterlands-belt.keys Winterlands)"

cbelt="$(screen "$crun" 0001-boots-on-belt.txt)"
ccarried="$(screen "$crun" 0002-sheet-carried.txt)"
cfeet="$(screen "$crun" 0003-boots-worn.txt)"
cworn="$(screen "$crun" 0004-sheet-worn.txt)"

grep -q "On Belt      :Boots +3 of the Winterlands" "$cbelt" || {
    echo "INCONCLUSIVE: no Boots +3 of the Winterlands reached a belt slot."
    echo "              Screen: $cbelt"
    exit 2
}
grep -q "Boots        :Boots +3 of the Winterlands" "$cfeet" || {
    echo "INCONCLUSIVE: the control boots never reached the feet, so the check"
    echo "              cannot tell an inert belt from an inert item."
    echo "              Screen: $cfeet"
    exit 2
}
grep -q "Resistances and Armour" "$ccarried" || {
    echo "INCONCLUSIVE: the sheet never scrolled to the resistance block."
    echo "              Screen: $ccarried"
    exit 2
}

if grep -q "Cold 9" "$ccarried"; then
    echo "FAIL: the Boots of the Winterlands pay from a belt slot. They promise"
    echo "      nothing about being carried, so the belt slot is now paying for"
    echo "      every item and the Providence reading above proves nothing."
    echo "      Screen: $ccarried"
    rc=1
fi
if ! grep -q "Cold 9" "$cworn"; then
    echo "INCONCLUSIVE: the control boots pay nothing even on the feet, so this"
    echo "              run cannot tell an inert belt from a broken item."
    echo "              Screen: $cworn"
    exit 2
fi

[ "$rc" = 0 ] && echo "  ok: the Boots of Providence pay their +3 Luck carried and worn, once,"
[ "$rc" = 0 ] && echo "      and only items whose page promises it pay from a belt slot"
exit $rc
