#!/bin/bash
# gate: live
# inc-drmm (port defect): a Large bearer's buckler must still cost -1.
# A seed-4 Human paladin acquires a buckler in wizard mode and learns Enlarge;
# one session reads the Medium and Large character sheets and both ready hands.
# Leather armour contributes zero to skills, leaving the buckler's term alone.
# --prove-red restores the original truncating division in the size loop.
# Observed --prove-red output (2026-09-11), with the Medium assertion passing:
#   |   FAIL  0/1 screens carry: Balance          +2  (0 ranks, +3 DEX, -1 armour)
#   |         it should prove: large buckler costs -1 to Balance
#   | FAIL: buckler costs -1 to Balance on both Medium and Large bearers
# PROVED RED: with src/Item.cpp mutated, this check exits 1.
. "$(dirname "$0")/check_lib.sh"
CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation src/Item.cpp \
    'for (; steps < 0; steps++) val = val < 0 ? min(-1, val / 2) : val / 2;' \
    'for (; steps < 0; steps++) val /= 2;'
check_run tools/keys/buckler-size.keys 4
for size in medium large; do
    check_screens "*-$size-hand"
    check_expect 'Ready Hand   :buckler' "$size bearer has the buckler readied"
    check_screens "*-$size-sheet"
    if [ "$size" = medium ]; then
        check_expect 'Human-sized (base human-sized)' 'Medium bearer before Enlarge'
    else
        check_expect 'Large (base human-sized, +1 magic)' 'Large bearer after Enlarge'
    fi
    check_expect 'Balance          +2  (0 ranks, +3 DEX, -1 armour)' \
        "$size buckler costs -1 to Balance"
done
check_done 'buckler costs -1 to Balance on both Medium and Large bearers'
