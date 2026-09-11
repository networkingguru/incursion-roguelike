#!/bin/bash
# gate: live
# inc-cmo5: the port's paged feat toggle must not spend a pick.
# Seed 7: h toggles 59 -> 224 -> 59 entries; the sheet keeps all three picks.
# --prove-red removes the conditional pos argument from GainFeat's LMenu call.
# Measured 2026-09-11, --prove-red (old call, exit 1):
#   FAIL  0/1 screens carry: [h] (Hide Unavailab
#   FAIL  0/1 screens carry: 52-102 of 224
#   FAIL  0/1 screens carry: [h] (Show All Feats)
#   FAIL  0/1 screens carry: 52-59 of 59
#   FAIL  0/1 screens carry: Alertness
#   FAIL  1/1 screens still carry: Battlefield Inspiration
#         first: Battlefield Inspiration
# FAIL: two toggle keypresses toggle twice and spend no feat pick
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation src/Create.cpp 'title,Win,"help::feats",focusToggle ? -1 : 0);' 'title,Win,"help::feats");'
check_run tools/keys/feat-toggle.keys 7
check_screens '*-initial-feats'
check_expect '1-51 of 59'
check_expect '[b] Alertness'
check_screens '*-toggle-before'
check_expect '[h] (Show All Feats)'
check_expect '52-59 of 59'
check_screens '*-toggle-on'
check_expect '[h] (Hide Unavailab'
check_expect '52-102 of 224'
check_screens '*-toggle-off'
check_expect '[h] (Show All Feats)'
check_expect '52-59 of 59'
check_screens '*-sheet-feats'
check_expect 'Feats:'
check_expect 'Alertness'
check_expect 'Iron Will'
check_expect 'Great Fortitude'
check_reject 'Battlefield Inspiration'
check_done 'two toggle keypresses toggle twice and spend no feat pick'
