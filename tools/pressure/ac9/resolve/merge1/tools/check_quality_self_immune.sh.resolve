# the function this change edits. The hit points and the item's name are the
# behavioural half.
@@@ next hunk
# WHY THE SCROLL ROLL IS FORCED. Each Enchant Armour read is a Decipher Script
# check and a high total preserves the scroll on a coin toss (src/Magic.cpp:6214).
# INCURSION_RUNTO_SKILL_ROLL=20 makes every read total 22: success, no preserve.
#
# Measured 2026-11-04 (inc-aoi4i), every seed: arm A ends at 46 of 56 hit
# points, named "mildly burnt leather armour", Fire still in its "0 to ..."
# group, no Fire on the sheet; arm B ends at 56 of 56, unburnt, Fire in its
# immunity list, and the sheet reads "Fire 6" once the suit is +2.
# tools/seed_sweep.sh: SEED-INDEPENDENT on seeds 101..505 and on 1 2 3 4 6 7 8 9.
# Usage: tools/check_quality_self_immune.sh [--prove-red]
# Declared mutation: Item::Hardness returns 0 instead of the -1 immunity.
# PROVED RED 2026-11-04, same five failures as 2026-09-11. Arm A stays green,
