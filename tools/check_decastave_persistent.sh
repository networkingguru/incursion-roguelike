#!/bin/bash
# gate: live
# Decastave lasts until the caster rests, and a held weapon-summoning spell
# refuses a second casting (bd inc-m790r).
#
# THE DEFECT. Decastave carried EF_DLONG, so its staff expired 100 + 10 x caster
# level rounds after the cast, while the spell's sibling Flame Blade (inc-wbq9)
# and every other buff lasts until the caster rests. Separately, a spell that
# summons a weapon (CREA_TEMP | CREA_WIELD) puts its SUMMONED stati on the ITEM,
# so the two "a second casting would have no effect" refusals in Creature::Cast
# never see it and a second cast made a second weapon.
#
# THE ORACLE is the game's own screen. Run 1 (tools/keys/decastave-persistent.keys)
# casts Decastave, wields the staff, passes time without resting, casts again,
# then takes a real rest. Run 2 (tools/keys/flame-blade-second-cast.keys) does the
# same for Flame Blade's conjure form, whose blade carries the sub-effect "flame
# blade;conjure" rather than the spell. The check asserts:
#   1. the staff is still in hand more than the old duration later (turn headers
#      of the dumps; 130 rounds = 65 units of 60 ticks = 3900 ticks)
#   2. the cast holds mana while the staff stands, and the rest gives it back
#   3. a second cast prints the refusal and makes no second staff
#   4. the rest ends the spell: the staff winks out
#   5. Flame Blade's conjure form refuses a second cast the same way
#
# PROVED RED by --prove-red, one site per run:
#   tools/check_decastave_persistent.sh --prove-red                 Decastave back to EF_DLONG
#   PR_SITE=cast tools/check_decastave_persistent.sh --prove-red    second-cast refusal disabled
#
# fact: characters -- fixtures orc-mage-seed4-opt0822 and druid-shoulder-metal-seed7-opt0822 (INCURSION_LOAD, built by tools/fixture_cache.sh)
# fact: settings -- CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: caster level 3, the spell known, the spell book, wizard switches, the depth 4 jump -- tools/keys/decastave-persistent.keys and tools/keys/flame-blade-second-cast.keys (wizard Free Advancement, Learn Spells table, Item Acquisition, Ascend / Descend Depth)
# fact: spell failure -- wizard switch Ignore Spell Failure
# fact: monsters interrupting the wait and the rest -- wizard switch Freeze Monsters
# fact: Flame Blade's "Augment or conjure?" answer -- the key 'c' in tools/keys/flame-blade-second-cast.keys
# fact: mana pool and hit points at level 3 -- not read: mana is compared only with itself (before cast, held, after rest)
# fact: elapsed time of the wait -- read from the dump headers' turn counter, never assumed from the key count
#
# Exit 0 pass, 1 the defect is present, 2 the check could not measure.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
OLD_DURATION_TICKS=3900   # 100 + 10 x level 3 = 130 rounds -> 65 units -> 65 x 60 ticks

[ -x ./incursion-headless ] || _check_die 2 \
    "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"

# One mutation per --prove-red run; PR_SITE chooses it.
if [ "${PR_SITE:-flags}" = cast ]; then
    check_mutation src/Magic.cpp \
        'if (HoldsSummonedItemOf(this, e.eID)) {' \
        'if (false && HoldsSummonedItemOf(this, e.eID)) {'
else
    check_mutation lib/wspells.irh \
        'Flags: EF_PERSISTANT, EF_LOSEMANA; Purpose: EP_BUFF (VS_MELEE);' \
        'Flags: EF_DLONG; Purpose: EP_BUFF (VS_MELEE);'
fi

# A long message wraps across screen lines; screen_shows (check_lib.sh) joins them.
expect_msg() { # <text> <what it proves>
    if screen_shows "$1" "${CHECK_SCREENS[@]}"; then
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1)); echo "  ok    $2"
    else
        echo "  FAIL  no chosen screen shows: $1"; echo "        it should prove: $2"; CHECK_FAIL=1
    fi
}

# turn_of <screen> -> the turn counter in the dump header
turn_of() { sed -n '1s/.* turn \([0-9]*\) ===.*/\1/p' "$1"; }
# mana_of <screen> -> "current max"
mana_of() { grep -o 'Mana:[0-9]*/[0-9]*' "$1" | head -1 | sed 's/Mana:\([0-9]*\)\/\([0-9]*\)/\1 \2/'; }
one_screen() { ls "$CHECK_RUN"/logs/screens/*"$1".txt 2>/dev/null | head -1; }

mkdir -p "$CHECK_ROOT/logs/runs"

# ---- run 1: Decastave --------------------------------------------------
export INCURSION_RUN_DIR="$(mktemp -d "$CHECK_ROOT/logs/runs/decastave-persistent.XXXXXX")"
INCURSION_LOAD=orc-mage-seed4-opt0822 check_run tools/keys/decastave-persistent.keys 1
unset INCURSION_RUN_DIR

wield="$(one_screen staff-wielded)"; waited="$(one_screen inventory-after-wait)"
before="$(one_screen before-cast)"; heldscr="$(one_screen mana-after-wait)"
second="$(one_screen second-cast)"; rested="$(one_screen mana-after-rest)"
afterinv="$(one_screen inventory-after-rest)"
for s in "$wield" "$waited" "$before" "$heldscr" "$second" "$rested" "$afterinv"; do
    [ -n "$s" ] || _check_die 2 "a dump the check reads is missing under $CHECK_RUN/logs/screens: the session did not get that far."
done

check_screens '*-staff-wielded'
check_expect "thundering force construct staff" "the cast made the staff and it stands in hand"
check_screens '*-inventory-after-wait'
check_expect "Weapon Hand  :thundering force construct staff" "the staff is still in the Weapon Hand after the wait"
elapsed=$(( $(turn_of "$waited") - $(turn_of "$wield") ))
if [ "$elapsed" -gt "$OLD_DURATION_TICKS" ]; then
    echo "  ok    the wait lasted $elapsed ticks, past the old $OLD_DURATION_TICKS (EF_DLONG at level 3)"
else
    echo "  FAIL  the wait lasted $elapsed ticks, not past the old duration of $OLD_DURATION_TICKS: the staff proves nothing"
    CHECK_FAIL=1
fi

read -r m0 mx0 <<< "$(mana_of "$before")"
read -r m1 mx1 <<< "$(mana_of "$heldscr")"
read -r m2 mx2 <<< "$(mana_of "$rested")"
if [ -n "${m0:-}" ] && [ -n "${m1:-}" ] && [ -n "${m2:-}" ] && [ "$m1" -lt "$m0" ] && [ "$m2" -eq "$m0" ]; then
    echo "  ok    mana held while the staff stands ($m0 -> $m1 after $elapsed ticks) and returned by the rest ($m2)"
else
    echo "  FAIL  mana before cast $m0, after the wait $m1, after the rest $m2: the cast must hold mana while the staff stands and the rest must return it"
    CHECK_FAIL=1
fi

check_screens '*-second-cast'
expect_msg "a second casting would have no effect" "a second cast of Decastave is refused"
check_reject "'In the Air':thundering force construct staff" "the refused cast made no second staff"

check_screens '*-mana-after-rest'
expect_msg "winks out of existence" "the rest ended the spell and the staff vanished"
check_screens '*-inventory-after-rest'
check_reject "Weapon Hand  :thundering force construct staff" "no staff stands in hand after the rest"

# ---- run 2: Flame Blade's conjure form -----------------------------------
export INCURSION_RUN_DIR="$(mktemp -d "$CHECK_ROOT/logs/runs/flame-blade-second.XXXXXX")"
INCURSION_LOAD=druid-shoulder-metal-seed7-opt0822 check_run tools/keys/flame-blade-second-cast.keys 1
unset INCURSION_RUN_DIR
check_screens '*-blade-wielded'
check_expect "Weapon Hand  :flame blade" "the conjured blade stands in hand"
check_screens '*-second-cast'
expect_msg "a second casting would have no effect" "a second cast of Flame Blade is refused while its blade is held"
check_reject "Augment or conjure" "the refused cast did not reach the conjure prompt"

check_done "Decastave lasts past its old duration until rest, and a held Decastave or Flame Blade refuses a second cast (inc-m790r)"
