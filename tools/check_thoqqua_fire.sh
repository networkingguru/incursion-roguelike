#!/bin/bash
# gate: live
# The thoqqua (lavaworm) MUST be immune to fire, as the other fire creatures
# are (bd inc-ejq).
#
# THE DEFECT. lib/mon4.irh defined the thoqqua as MA_FIRE with a 2d6 fire aura
# and no Immune: line, so it took the fire creature's weakness to cold and
# none of its protection, and eating its corpse granted no resistance.
#
# THE ORACLE is the wizard's Examine Nearby Things screen (src/Debug.cpp),
# whose Resists: block prints the creature's live ResistLevel per damage type;
# -1 is immunity. The key script summons a thoqqua and opens that screen. A
# screen that never names the thoqqua is a FAIL.
#
# Usage: tools/check_thoqqua_fire.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation lib/mon4.irh \
'       Tracked as inc-ejq. Not sent. */
    Immune: DF_FIRE;' \
'       Tracked as inc-ejq. Not sent. */'

check_run tools/keys/thoqqua-fire-immunity.keys 5
check_screens '*examined*'
check_expect "thoqqua (class T_MONSTER" "the screen examined is the thoqqua's"
check_expect "A_AURA for 2d6 AD_FIRE" "it is the creature with the fire aura"
check_expect "  Fire -1 (bypass" "its Resists block lists fire at -1, immune"
check_done "the thoqqua is immune to fire (inc-ejq)"
