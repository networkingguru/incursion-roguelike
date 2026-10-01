#!/bin/bash
# gate: live
# gate-serial: pins a fixed INCURSION_RUN_DIR (logs/runs/necro-undead-pool-*) shared by two runs
# Does a Necromancer's bonus undead pool reach PHD_UNDEAD, the pool Animate
# Dead and Create Undead charge created undead to? (bd inc-1n74)
#
# THE DEFECT. lib/classes.irh gives a level-1 Necromancer BONUS_PHD of
# magnitude 1 -- one point of an extra companion pool. Upstream grants it
# against PHD_COMMAND, but a pure mage has no CA_COMMAND, so MaxGroupCR
# (PHD_COMMAND) is -10 and the grant does nothing: the Necromancer's bonus pool
# is invisible and created undead are charged to PHD_MAGIC alone, like any other
# mage. The fix grants it against PHD_UNDEAD instead, which MaxGroupCR returns
# straight from HighStatiMag(BONUS_PHD, PHD_UNDEAD) (src/Social.cpp:2597), so
# the bonus is real.
#
# THE ORACLE is the wizard-mode "Group CR Totals" block of Player::Dump
# (src/Debug.cpp:1725), read in play with no probe. The PHD_UNDEAD line's
# second number is MaxGroupCR(PHD_UNDEAD), which is exactly the grant.
#
#   Necromancer, no undead yet    PHD UNDEAD  -8 / 1   (bonus pool: max 1)
#   any other mage, no undead     PHD UNDEAD  -8 / 0   (no such pool)
#
# Then a wight is created with the wizard's Create Corporeal Undead, which calls
# Monster::MakeCompanion(PHD_UNDEAD) (lib/abilities.irh:177). Both mages keep
# it, but the accounting differs, and the dump shows it:
#
#   Necromancer, after the wight  PHD UNDEAD  2 / 1 and PHD MAGIC   1 / 1
#   other mage, after the wight   PHD UNDEAD  2 / 0 and PHD MAGIC   2 / 1
#
# The same wight overflows into PHD_MAGIC from the two different pool widths
# (MaxGroupXCR 64 against 55, XCR(1) vs XCR(0)), so the Necromancer's magic
# reading is one CR lower. Under the defect the Necromancer reads exactly like
# the other mage, and check_reject catches that.
#
# WHY THE CHECK GENERATES ITS OWN CHARACTERS. The grant is written at character
# creation (mage level 1) and is stored in a save. A frozen fixture made with
# the FIXED lib already holds the PHD_UNDEAD grant, so loading it on the old
# code would still show a working pool and the check would not go red. Both
# characters here are therefore built by chargen inside these runs.
#
# WHY THE TWO MAGES KEEP THE SAME UNDEAD COUNT. A level-1 mage's PHD_MAGIC and
# PHD_PARTY pools (XCR(1)=64 and XCR(3)=216) absorb a wight (XCR(3)=216) for
# both schools, and the two MaxGroupCR(PHD_UNDEAD) values (1 and 0) differ by
# only 9 XCR units. The pools diverge in what the wight is *charged against*,
# not in whether it is kept; a keep/refuse split would need a CR-4 undead
# (XCR(4)=343 lands in the 9-wide window at level 1), and no level-1 spell of
# either school can raise one. The observation is the accounting difference,
# not a count difference, and this check does not pretend otherwise.
#
# The admission chain (undead -> magic -> party) in Monster::MakeCompanion
# is Traced only: its old and new rules differ only while the magic pool has
# headroom, and a level-1 wight already overflows it, so no level-1 run
# separates them.
#
# Usage: tools/check_necro_undead_pool.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# Break the fix at its site: put the grant back on PHD_COMMAND, where the
# mage has no ability to carry it. The Necromancer's PHD UNDEAD max
# collapses to 0 and every assertion below reads the plain-mage reading.
check_mutation lib/classes.irh \
    'SS_CLAS,PHD_UNDEAD,1,$"mage",0);' \
    'SS_CLAS,PHD_COMMAND,1,$"mage",0);'

# --- the Necromancer, generated in-run ---
export INCURSION_RUN_DIR="logs/runs/necro-undead-pool-necro"
check_run tools/keys/necro-undead-pool-necro.keys 1

check_screens '*-group-before'
check_expect "PHD UNDEAD  -8 / 1" \
    "a generated Necromancer has a bonus undead pool of max 1"
check_reject "PHD UNDEAD  -8 / 0" \
    "the grant is not sitting on PHD_COMMAND, where a pure mage could not use it"

check_screens '*-raised'
check_expect "The dead rise!" \
    "Create Corporeal Undead called MakeCompanion(PHD_UNDEAD) and kept the wight"

check_screens '*-group-after'
check_expect "PHD UNDEAD  2 / 1" \
    "the wight is charged against the Necromancer's bonus undead pool"
check_expect "PHD MAGIC   1 / 1" \
    "and its overflow into the magic pool is exactly one CR"
check_reject "PHD UNDEAD  2 / 0" \
    "the Necromancer does not read like a mage with no undead pool"

# Cast 2: still admitted -- undead, then magic, both still have room.
check_screens '*-cast2'
check_expect "The dead rise!" \
    "cast 2 also creates a wight; MakeCompanion(PHD_UNDEAD) admits it too"

check_screens '*-group2'
check_expect "PHD UNDEAD  4 / 1" \
    "two wights are charged against the Necromancer's undead pool"
check_expect "PHD MAGIC   3 / 1" \
    "their combined overflow into magic grows with the second wight"

# Cast 3: refused -- undead + magic + party are now full. This is the count
# the accounting chain bounds; the caller's own refusal text proves it, not
# just an unmoved pool reading.
check_screens '*-cast3'
check_expect "shifts briefly, but does not move" \
    "cast 3 is REFUSED: MakeCompanion(PHD_UNDEAD) returned false"

check_screens '*-group3'
check_expect "PHD UNDEAD  4 / 1" \
    "the refused cast 3 did not move the undead pool"
check_reject "PHD UNDEAD  6 / 1" \
    "no third wight was admitted"

# Casts 4 and 5: still refused. The pool does not merely stall once -- it
# stays bounded at N=2 for every further attempt in this run.
check_screens '*-cast4'
check_expect "shifts" \
    "cast 4 is refused the same way as cast 3"
check_reject "The dead rise!" \
    "cast 4 is not admitted"
check_screens '*-cast5'
check_expect "shifts" \
    "cast 5 is refused the same way as cast 3"
check_reject "The dead rise!" \
    "cast 5 is not admitted"
check_screens '*-group[45]'
check_expect_all "PHD UNDEAD  4 / 1" \
    "the pool holds at N=2 through casts 4 and 5"
check_reject "PHD UNDEAD  6 / 1" \
    "no later cast slipped through"

# --- the non-specialist, generated in-run, same seed and settings ---
export INCURSION_RUN_DIR="logs/runs/necro-undead-pool-mage"
check_run tools/keys/necro-undead-pool-mage.keys 1

check_screens '*-group-before'
check_expect "PHD UNDEAD  -8 / 0" \
    "a non-Necromancer has no bonus undead pool at all"
check_reject "PHD UNDEAD  -8 / 1" \
    "the bonus is granted to Necromancers only"

check_screens '*-raised'
check_expect "The dead rise!" \
    "the same spell and the same corpse create a wight for the other mage"

check_screens '*-group-after'
check_expect "PHD UNDEAD  2 / 0" \
    "the other mage keeps the wight with no undead pool to charge it to"
check_expect "PHD MAGIC   2 / 1" \
    "so the wight overflows into magic from a narrower pool, one CR higher"
check_reject "PHD MAGIC   1 / 1" \
    "the other mage does not get the Necromancer's undead-pool relief"

# Cast 2: still admitted, same as the Necromancer's run.
check_screens '*-cast2'
check_expect "The dead rise!" \
    "cast 2 also creates a wight for the other mage"

check_screens '*-group2'
check_expect "PHD UNDEAD  4 / 0" \
    "two wights are charged against the other mage's (nonexistent) undead pool"
check_expect "PHD MAGIC   3 / 1" \
    "their overflow into magic matches the same finite bound"

# Cast 3: refused, at the same count as the Necromancer -- the bound is on
# the accounting chain, not on which school holds the bonus.
check_screens '*-cast3'
check_expect "shifts briefly, but does not move" \
    "cast 3 is REFUSED for the other mage too"

check_screens '*-group3'
check_expect "PHD UNDEAD  4 / 0" \
    "the refused cast 3 did not move the other mage's undead pool"
check_reject "PHD UNDEAD  6 / 0" \
    "no third wight was admitted"

# Casts 4 and 5: still refused; the bound holds for the rest of the run.
check_screens '*-cast4'
check_expect "shifts" \
    "cast 4 is refused the same way as cast 3"
check_reject "The dead rise!" \
    "cast 4 is not admitted"
check_screens '*-cast5'
check_expect "shifts" \
    "cast 5 is refused the same way as cast 3"
check_reject "The dead rise!" \
    "cast 5 is not admitted"
check_screens '*-group[45]'
check_expect_all "PHD UNDEAD  4 / 0" \
    "the pool holds at N=2 through casts 4 and 5 for the other mage too"
check_reject "PHD UNDEAD  6 / 0" \
    "no later cast slipped through"

check_done "the Necromancer's bonus feeds PHD_UNDEAD, a created undead is charged against it, and the undead-magic-party chain bounds every mage's created undead at a finite, refused count"
