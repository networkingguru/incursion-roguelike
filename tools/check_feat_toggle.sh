#!/bin/bash
# gate: live
# inc-cmo5: the port's paged feat toggle must not spend a pick.
# On the "Choose a feat" menu, the key script presses the (Show All Feats)
# entry, then the (Hide Unavailab...) entry, by name. Each press toggles; none
# spends a feat pick. The sheet keeps the picks the script names (Great
# Fortitude, Alertness) and never shows Battlefield Inspiration, the bug's own
# symptom. The count of available feats, N, is read from the run's
# "1-51 of N" line; the full list must show "52-102 of M" with M > N.
#
# fact: settings -- pinned tools/fixtures/options-2026-08-22.dat
# fact: race, class, god -- chosen by name in tools/keys/feat-toggle.keys (Human, Paladin, Erich)
# fact: alignment -- Paladin offers one; the script takes the first offered
# fact: attribute scores -- Point Buy in tools/keys/feat-toggle.keys (no roll)
# fact: perks -- none under Point Buy, so no random bonus feat
# fact: available feat count N -- read from the run's "1-51 of N" line, not hard-coded
# fact: the toggle's menu letter -- the key script presses the entry by name, so the count cannot move it
# fact: sheet feats -- the feats the key script picks by name
#
# --prove-red removes the conditional pos argument from GainFeat's LMenu call.
# Historical measurement, 2026-09-11 (old call, exit 1; seed-7 roll, 59 feats):
#   FAIL  0/1 screens carry: [h] (Hide Unavailab
#   FAIL  0/1 screens carry: 52-102 of 224
#   FAIL  0/1 screens carry: [h] (Show All Feats)
#   FAIL  0/1 screens carry: 52-59 of 59
#   FAIL  0/1 screens carry: Alertness
#   FAIL  1/1 screens still carry: Battlefield Inspiration
# Measured 2026-11-16, Point Buy build, --prove-red (old call, exit 1; N = 60):
#   FAIL  0/1 screens carry: ] (Hide Unavailab
#   FAIL  toggle-on screen needs "52-102 of M" with M > 60; found: no such line
#   FAIL  0/1 screens carry: ] (Show All Feats)
#   FAIL  0/1 screens carry: 52-60 of 60
# FAIL: two toggle keypresses toggle twice and spend no feat pick
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation src/Create.cpp 'title,Win,"help::feats",focusToggle ? -1 : 0);' 'title,Win,"help::feats");'
check_run tools/keys/feat-toggle.keys 7
check_screens '*-initial-feats'
n="$(grep -ho -- '1-51 of [0-9]*' "${CHECK_SCREENS[@]}" 2>/dev/null | head -1 | sed 's/.* //')"
if [ -z "$n" ]; then
    printf '  FAIL  initial-feats screen has no "1-51 of N" line\n'
    CHECK_FAIL=1
    n=0
else
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    printf '  ok    initial-feats screen shows 1-51 of %s\n' "$n"
fi
check_expect '[b] Alertness'
check_screens '*-toggle-before'
check_expect '] (Show All Feats)'
check_expect "52-$n of $n"
check_screens '*-toggle-on'
check_expect '] (Hide Unavailab'
# M in "52-102 of M" is the full feat list; it must exceed the N available.
total="$(grep -ho -- '52-102 of [0-9]*' "${CHECK_SCREENS[@]}" 2>/dev/null | head -1 | sed 's/.* //')"
if [ -n "$total" ] && [ "$n" -gt 0 ] && [ "$total" -gt "$n" ]; then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    printf '  ok    full feat list shows 52-102 of %s (> %s)\n' "$total" "$n"
else
    printf '  FAIL  toggle-on screen needs "52-102 of M" with M > %s; found: %s\n' "$n" "${total:-no such line}"
    CHECK_FAIL=1
fi
check_screens '*-toggle-off'
check_expect '] (Show All Feats)'
check_expect "52-$n of $n"
check_screens '*-sheet-feats'
check_expect 'Feats:'
check_expect 'Alertness'
check_expect 'Great Fortitude'
check_reject 'Battlefield Inspiration'
check_done 'two toggle keypresses toggle twice and spend no feat pick'
