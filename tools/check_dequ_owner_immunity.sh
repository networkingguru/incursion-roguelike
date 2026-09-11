#!/bin/bash
# Rust immunity protects the owner's gear (bd inc-w26h).
#
# THE RULE. Soak and rust defences protect gear regardless of the grant's flag;
# other damage types require EF_PROTECTS_ITEMS. This guards the blanket rust
# half through gameplay, with the route itself checked by check_item_owner_resist.sh.
# WHY BLANKET RUST. src/Fight.cpp:7009-7040 damages an item in the rust case
# and never costs the creature hit points, so a wearer-only grant is a no-op.
#
# WHY THESE GAUNTLETS. Gauntlets of Rust grant total rust immunity, which the
# sheet must list as Rusting under Complete Immunities. They also carry
# EF_PROTECTS_ITEMS, so deleting either protection route leaves the other.
# The single mutation instead breaks their shared Item::Damage delivery point:
# replace the immunity return with gear = 0. Merely using if (0) leaves gear
# at -1, which turns iron's zero hardness into the item-immunity sentinel.
#
# WHY A SMALL MUD ELEMENTAL. Its A_DEQU is 1d6 AD_RUST (lib/mon4.irh:2396).
# Iron has hardness 0 against rust, so each unprotected retaliation that lands
# does its whole roll. Frozen monsters still retaliate when hit; one elemental
# per blow avoids killing the target and losing the retaliation's item target.
# WHY A MAUL. At 262 hit points it is the heaviest ordinary weapon in lib/;
# five retaliations cannot destroy it and leave no page to read. It is iron,
# which is what rusts.
#
# Measured 2026-09-10, seed 5: intact 262/262 before -> 262/262 after;
# delivery point broken 262/262 before -> 258/262 after, with a rust message.
# Usage: tools/check_dequ_owner_immunity.sh [--prove-red]
# Exact --prove-red output (outer exit 0):
#   re-running /Users/brianhill/Scripts/Incursion-w26h/tools/check_dequ_owner_immunity.sh before mutation
#   |   session: /Users/brianhill/Scripts/Incursion-w26h/logs/runs/20260910-204046-2593-dequ-owner-immunity (seed 5, options-2026-08-22.dat)
#   |   screens: 1 matching '*-immune-sheet'
#   |   ok    1/1 screens: the character sheet lists immunities
#   |   ok    1/1 screens: rust immunity is active on the character
#   |   screens: 1 matching '*-immune-before'
#   |   ok    1/1 screens: the character wields an ordinary iron maul
#   |   ok    1/1 screens: the maul starts undamaged
#   |   screens: 1 matching '*-immune-after'
#   |   ok    1/1 screens: the maul remains undamaged after five blows
#   |   screens: 9 matching '*'
#   |   ok    0/9 screens: no screen reports rust damage to the maul
#   | 
#   | PASS: rust immunity protects the owner's maul
#   |       (/Users/brianhill/Scripts/Incursion-w26h/logs/runs/20260910-204046-2593-dequ-owner-immunity/logs/screens)
# --- prove red: src/Item.cpp ---
#   mutating   src/Item.cpp  (original copied to /var/folders/jj/knm0d3jd2hxg9_0_rs37knr40000gn/T/check_prove_red.3Kqc40axcv/original)
#              this is the first mutation the check declares; a later
#              one is not reached by this run.
#   building incursion-headless ... ok
#   re-running /Users/brianhill/Scripts/Incursion-w26h/tools/check_dequ_owner_immunity.sh with the fix broken
# 
#   |   session: /Users/brianhill/Scripts/Incursion-w26h/logs/runs/20260910-204108-10769-dequ-owner-immunity (seed 5, options-2026-08-22.dat)
#   |   screens: 1 matching '*-immune-sheet'
#   |   ok    1/1 screens: the character sheet lists immunities
#   |   ok    1/1 screens: rust immunity is active on the character
#   |   screens: 1 matching '*-immune-before'
#   |   ok    1/1 screens: the character wields an ordinary iron maul
#   |   ok    1/1 screens: the maul starts undamaged
#   |   screens: 1 matching '*-immune-after'
#   |   FAIL  0/1 screens carry: It has 262 out of 262 hit
#   |         it should prove: the maul remains undamaged after five blows
#   |   screens: 9 matching '*'
#   |   FAIL  1/9 screens still carry: Your maul rusts
#   |         it should prove: no screen reports rust damage to the maul
#   |         first: Your maul rusts
#   | 
#   | FAIL: rust immunity protects the owner's maul
#   |       the screens are in /Users/brianhill/Scripts/Incursion-w26h/logs/runs/20260910-204108-10769-dequ-owner-immunity/logs/screens
# 
#   restoring  src/Item.cpp
#   removed incursion-headless -- it may have been linked from the mutated src/Item.cpp.
#   Rebuild with: BACKEND=posix ./build_macos.sh
#   building incursion-headless ... ok
# 
# PROVED RED: with src/Item.cpp mutated, this check exits 1.
#             Record the mutation and this line where the work is.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation src/Item.cpp \
'        if (gear == -1)
            return DONE;' \
'        if (gear == -1)
            gear = 0;'

check_run tools/keys/dequ-owner-immunity.keys 5
check_screens '*-immune-sheet'
check_expect "Complete Immunities:" "the character sheet lists immunities"
check_expect "Rusting" "rust immunity is active on the character"
check_screens '*-immune-before'
check_expect "The Uncursed Maul ('" "the character wields an ordinary iron maul"
check_expect "It has 262 out of 262 hit" "the maul starts undamaged"
check_screens '*-immune-after'
check_expect "It has 262 out of 262 hit" "the maul remains undamaged after five blows"
check_screens
check_reject "Your maul rusts" "no screen reports rust damage to the maul"
check_done "rust immunity protects the owner's maul"
