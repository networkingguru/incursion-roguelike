#!/bin/sh
# gate: live
# Does a mount keep its own aura, and keep owning it?
#
# bd inc-izzy. Two defects, one journey. Climbing onto an animal used to
# destroy the aura it was emitting, because Creature::Mount takes the animal
# off the map with Thing::Remove and that function reaps mobile fields. One
# staircase later, Thing::PlaceAt used to re-create the animal's aura with the
# RIDER named as its creator, which is what put four "Spook" rows in one
# player's dismiss menu.
#
# Five states, measured in one run of tools/keys/spook-mount.keys on seed 2.
# The numbers below are what this script asserts; the key script's header
# explains why each one reads the way it does.
#
#                                    before the fix        after it
#   1 tamed bat, player on foot      Hit 4, Spook shown    Hit 4, Spook shown
#   2 the same bat, ridden           Hit 7, no Spook       Hit 5, Spook shown
#   3 dismounted, out of the radius  Hit 6, no Spook       Hit 6, no Spook
#     and back in
#   4 mounted again after that       Hit 7, no Spook       Hit 7, no Spook
#   5 one staircase later, ridden    "Drop Spook" listed   not listed
#
# States 3 and 4 are the ones that describe play: an animal you own must never
# demoralize you, on foot or in the saddle. The -2 in states 1 and 2 is a debt
# from before the bat was tame -- wizard mode summons it hostile and taming
# does not scrub a penalty already taken -- and it is the only witness this
# run has to the aura surviving the climb, because a player who is immune on
# entry cannot tell a live aura from a dead one.
#
# State 1 is the control for states 2 and 5. It fails if a "fix" merely stops
# the bat casting. State 5 has its own control: the "Dismount" row must be
# present, which proves the menu drew at all.
#
# State 3's before-column needs the mount fix in place to appear at all --
# with neither fix there is no aura left to hand over. It was measured on
# 2026-08-22 with Thing::Remove fixed and Thing::PlaceAt not, and it printed
# "[b] Drop Spook".
#
# THE NUMBERS ABOVE ARE OFFSETS, NOT ABSOLUTES. "Hit 4" is the loaded orc's own
# Hit plus the morale term, and a character rolled from the seed moves it. This
# check loads a frozen character and reads the Hit line relative to the one state
# with no penalty and no saddle bonus (state 3, on foot after re-entry), which
# is the character's base Hit (it reads 6 for the fixture, but nothing asserts
# that). The other states are asserted at their offsets from it:
#   state 1  base - 2   the debt from when the bat was hostile
#   state 2  base - 1   the same debt, and the +1 for riding
#   state 3  base       no penalty, on foot
#   state 4  base + 1   no penalty, and the +1 for riding
#
# fact: character (orc warrior) -- fixture spook-mount-seed5-opt0822, INCURSION_LOAD
# fact: Hit before any penalty -- read from state 3 and asserted as offsets from it
# fact: the hostile bat's aura save fails (the -2 debt) -- INCURSION_FORCE_SAVE_ROLL=1
# fact: the night hunter and the taming -- wizard Monster Summoning, Make Player Master of Monster
# fact: Freeze Monsters on -- wizard Wizard Mode Switches (tools/keys/spook-mount-loaded.keys)
# fact: stairs and depth -- wizard Ascend / Descend Depth
set -e

cd "$(dirname "$0")/.."

# The save the bat's aura rolls is a die; force it to a natural 1, which always
# fails, so the debt in states 1 and 2 is always taken.
export INCURSION_FORCE_SAVE_ROLL=1
export INCURSION_LOAD=tools/fixtures/chars/spook-mount-seed5-opt0822.sav
RUN=$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat ./tools/headless.sh tools/keys/spook-mount-loaded.keys 2 2>&1 | sed -n 's/^run:  *//p')
[ -n "$RUN" ] || { echo "FAIL: the run produced no directory"; exit 1; }
S="$RUN/logs/screens"

hit() {
    grep -o 'Hit:[0-9-]*' "$1" | head -1 | cut -d: -f2
}

fail=0

base=$(hit "$S/0003-re-entered.txt")
case "$base" in
    ''|*[!0-9-]*) echo "INCONCLUSIVE: no Hit in $S/0003-re-entered.txt, so there is no base to measure from"; exit 2 ;;
esac
echo "  base Hit (state 3, no penalty, on foot): $base"

on_foot=$(hit "$S/0001-on-foot.txt")
if [ "$on_foot" = "$((base - 2))" ]; then
    echo "  ok: the debt from when the bat was hostile is still on him (base - 2)"
else
    echo "  FAIL: on foot, expected Hit $((base - 2)), read Hit ${on_foot:-none}"
    fail=1
fi

if tail -1 "$S/0001-on-foot.txt" | grep -q "Spook"; then
    echo "  ok: and his status line names it, so there is a witness to carry"
else
    echo "  FAIL: on foot, the status line does not name Spook"
    fail=1
fi

mounted=$(hit "$S/0002-mounted.txt")
if [ "$mounted" = "$((base - 1))" ]; then
    echo "  ok: the aura survives the climb (base - 1, which is base - 2 and the +1 for riding)"
else
    echo "  FAIL: mounted, expected Hit $((base - 1)), read Hit ${mounted:-none}"
    fail=1
fi

if tail -1 "$S/0002-mounted.txt" | grep -q "Spook"; then
    echo "  ok: the status line still names it while he rides"
else
    echo "  FAIL: mounted, the status line no longer names Spook"
    fail=1
fi

re_entered=$(hit "$S/0003-re-entered.txt")
if [ "$re_entered" = "$base" ]; then
    echo "  ok: on foot, an animal he owns does not demoralize him (the base Hit)"
else
    echo "  FAIL: after re-entry on foot, expected Hit $base, read Hit ${re_entered:-none}"
    fail=1
fi

if tail -1 "$S/0003-re-entered.txt" | grep -q "Spook"; then
    echo "  FAIL: after re-entry on foot, the status line still names Spook"
    fail=1
else
    echo "  ok: and his status line does not name Spook"
fi

mounted_clean=$(hit "$S/0004-mounted-clean.txt")
if [ "$mounted_clean" = "$((base + 1))" ]; then
    echo "  ok: nor does it demoralize him in the saddle (base + 1, the base and the +1)"
else
    echo "  FAIL: mounted after re-entry, expected Hit $((base + 1)), read Hit ${mounted_clean:-none}"
    fail=1
fi

if tail -1 "$S/0004-mounted-clean.txt" | grep -q "Spook"; then
    echo "  FAIL: mounted after re-entry, the status line still names Spook"
    fail=1
else
    echo "  ok: and his status line does not name Spook there either"
fi

if grep -q "Dismount the night hunter" "$S/0005-dismiss-after-stairs.txt"; then
    echo "  ok: the dismiss menu drew after the staircase"
else
    echo "  FAIL: the dismiss menu did not draw after the staircase"
    fail=1
fi

if grep -q "Drop Spook" "$S/0005-dismiss-after-stairs.txt"; then
    echo "  FAIL: after the staircase the aura is listed as the player's own"
    fail=1
else
    echo "  ok: after the staircase the aura is still the animal's, not his"
fi

if [ "$fail" = "0" ]; then
    echo "PASS: an animal you own never demoralizes you, on foot or mounted,\n      it keeps the aura it is emitting when you climb on,\n      and that aura is still its own after a staircase"
    exit 0
fi

echo "FAIL: see $S"
exit 1
