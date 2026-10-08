#!/bin/bash
# gate: live
# inc-3ax: the swap-weapons command must not print a false
# "You fumble the items you were trying to exchange, dropping them!" when it
# fails BEFORE it picks up any item.
#
# WHAT IS BEING GUARDED. Character::Exchange (src/Inv.cpp) has failure paths
# that jump to the XAbort label. XAbort unconditionally prints the fumble line
# and then calls PlaceAt on whichever of old1/old2/new1/new2 is non-NULL. The
# EARLY failure paths -- no default melee or ranged weapon set, a default
# weapon not accessible, no default selected -- reach XAbort with all four
# pointers still NULL, so nothing is dropped, and before inc-3ax the player
# still read "You fumble ... dropping them!" right after the correct
# explanatory line. The LATER paths (no free slot, a failed Swap) really do
# drop items, so the fumble line is correct there and must stay.
#
# THE ORACLE is two screen dumps from one session. A frozen fixture with no
# default weapons is loaded and '-' is pressed: the after-dash dump must carry
# the explanatory "default melee and ranged" line, which is the proof the
# early path ran at all, and no chosen dump may carry the fumble line. The
# check FAILS (exit 2) if it cannot find the explanatory line, so it cannot
# pass by never reaching the code.
#
# Usage: tools/check_exchange_no_false_fumble.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

SEED=1
KEYS=tools/keys/exchange-no-defaults.keys
LOAD=tools/fixtures/chars/lizardfolk-monk-seed1.sav

[ -f "$LOAD" ] || _check_die 2 \
    "no $LOAD, so there is no frozen character with no default weapons." \
    "The fixture is committed under tools/fixtures/chars/."

# Every run gets its own run directory under logs/.
export INCURSION_RUN_DIR="$CHECK_ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-exchange-no-defaults"
export INCURSION_LOAD="$LOAD"

check_run "$KEYS" "$SEED"

# The explanatory line wraps across two screen lines; this fragment sits wholly
# on one of them ("You need to set your default melee and ranged").
check_screens
check_expect "default melee and ranged" \
    "the session reached Character::Exchange's early no-defaults path"

# The fumble line also wraps; this fragment sits wholly on one line.
# It must appear on NO dumped screen while no item was dropped.
check_reject "fumble the items you were trying to exchange" \
    "the early path drops nothing, so it must not print the fumble line"

check_done "the no-defaults early path explains itself without a false fumble"
