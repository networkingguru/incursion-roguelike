#!/bin/bash
# gate: live
# Can a new Rogue 1 with Dexterity below 13 take Weapon Finesse? (bd inc-dkbaw)
#
# THE RULE. Weapon Finesse has no prerequisites (Pathfinder 1e Core Rulebook,
# owner ruling 2026-10-31). src/FeatTab.cpp used to require Dexterity 13 and
# melee BAB +1, or CA_UNARMED_STRIKE. A Rogue 1 has melee BAB +0, so the feat
# was never offered to him.
#
# THE ORACLE. Character generation of an orc Rogue with Dexterity 11 (tools/keys/
# weapon-finesse-rogue.keys): the first-feat menu must list Weapon Finesse, the
# script chooses it, and the character sheet written by Save and Continue
# (INCURSION_CHAR_PROBE=1, logs/charprobe.txt) must list it among his feats.
# A missing menu or sheet is INCONCLUSIVE (exit 2), never a pass.
#
# fact: character race, class, stats -- generated in the run; Point Buy STR 17 DEX 11 (below the old 13), shown on the points screen
# fact: melee BAB +0 -- every Rogue 1 has it; no dice, no control needed
# fact: settings -- options-2026-08-22.dat (CHECK_OPTIONS)
# fact: the feat menu and the sheet -- the dumped screens and logs/charprobe.txt; no dice
#
# Usage: tools/check_weapon_finesse_prereq.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_CHAR_PROBE=1

# Break the fix at its site: restore the old prerequisite rows.
check_mutation src/FeatTab.cpp \
    '{{{FP_ALWAYS}}}}, /* inc-dkbaw: no prerequisites, per Pathfinder 1e */' \
    '{{{FP_ATTR,A_DEX,13,  FP_BAB,S_MELEE,1},
      {FP_ABILITY,CA_UNARMED_STRIKE,1}}}},'

export INCURSION_RUN_DIR="logs/runs/weapon-finesse-rogue"
check_run tools/keys/weapon-finesse-rogue.keys 1

check_screens '*-points'
check_expect "DEX  11" "the Rogue's Dexterity is 11, below the old requirement of 13"

check_screens '*-feat-page2'
check_expect "[a] Weapon Finesse" "the first-feat menu offers Weapon Finesse to a Rogue 1 with DEX 11"

# The sheet is not a screen dump: copy it where check_screens reads.
sheet="$CHECK_RUN/logs/charprobe.txt"
[ -f "$sheet" ] || _check_die 2 "no $sheet: the run never saved the character, so the sheet is unread"
cp "$sheet" "$CHECK_RUN/logs/screens/9999-sheet.txt"
check_screens '*-sheet'
check_expect "Weapon Finesse" "the saved character sheet lists Weapon Finesse"

check_done "a Rogue 1 with Dexterity 11 and melee BAB +0 is offered Weapon Finesse and ends with it"
