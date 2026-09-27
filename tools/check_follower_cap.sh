#!/bin/bash
# gate: live
# Do companion ("PHD") pools charge followers at the same scale as their limit,
# and does a full pool charge its deficit to the party pool? (bd inc-omm1)
#
# TWO FAULTS, ONE CHECK, both read off the wizard-mode "Group CR Totals" block
# of Player::Dump (src/Debug.cpp:1730), which prints GetGroupCR / MaxGroupCR
# for each pool. GetGroupCR is XCRtoCR of GetGroupXCR (inc/Creature.h:1331), so
# a wrong XCR anywhere in the pool moves the printed CR.
#
#   FAULT 1 -- SCALE. Player::GetGroupXCR charged each follower
#   max(10,(j+2)^3) while the limit side is MaxGroupXCR = XCR(MaxGroupCR) =
#   (CR+3)^3 (inc/Inline.h:774). Every follower counted one CR lower than it
#   is, because (j+2)^3 = XCR(j-1). The fix charges XCR(j).
#
#   FAULT 2 -- THE FULL POOL. Monster::MakeCompanion computed its admission
#   test by rounding through XCRtoCR:
#       Total = XCRtoCR(XCR(MaxGroupCR(ct)) - XCR(GetGroupCR(ct, newCR)));
#   XCRtoCR of a zero or negative remainder returns -8, and XCR(-8) is +10, so
#   a creature's pool deficit collapsed to a nominal +10 and was never charged
#   against the party pool. The fix tests XCR units directly and charges the
#   real deficit to PHD_PARTY.
#
# THE ORACLE is the printed pool CR, in play, with no probe:
#
#   control (fault 1)  A level-1 orc mage (CHA 14: PHD_MAGIC max CR 1 = XCR 64,
#     PHD_PARTY max CR 3 = XCR 216) dominates a summoned kobold of CR 0.
#     Correct, the kobold costs XCR(0)=55 -> PHD MAGIC reads  0 / 1.
#     Upstream, max(10,(0+2)^3)=10 -> XCRtoCR(10)=-8 -> PHD MAGIC reads -8 / 1.
#
#   subject (fault 2)  The same mage then dominates a summoned hill giant
#     (CR 7, cost XCR(7)=1000). Correct, own = 55+1000-64 = 991 > 0 and
#     partyAfter = 0+991 = 991 > 216, so MakeCompanion REFUSES: the giant
#     breaks free ("The hill giant breaks free of your control!") and both
#     pools stay at the control reading. Upstream, the 991 deficit became +10,
#     the party test passed, and the giant joined the party: PHD MAGIC read
#     8 / 1 and PHD PARTY read 7 / 3.
#
# Both tests are deterministic on seed 1: the giant is dominated through its
# Will save by natural-1 retries (a natural 1 always fails, src/Creature.cpp:
# 3596), and the refusal save is drawn from the same fixed sequence.
#
# The mutation below breaks fault 2 (the giant is admitted again); the manual
# red proof recorded with this bead broke both sites at once. See the bead note.
#
# Usage: tools/check_follower_cap.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# Declare how to break the fix, so --prove-red can. This is the fault-2 site:
# forcing the admission makes the giant a companion again and moves PHD MAGIC
# and PHD PARTY, which the assertions read.
check_mutation src/Social.cpp \
    '        refuse = own > 0 && partyAfter > p->MaxGroupXCR(PHD_PARTY);' \
    '        refuse = false;'

# A frozen character, not a generated one: an rID is a POSITION, so a lib/
# change silently rebuilds a seed-pinned character (tools/fixtures/README.md).
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed1-opt0822.sav
check_run tools/keys/follower-cap.keys 1

# The giant really was dominated before the refusal, so an unchanged pool
# reading cannot be the "never reached the state" mistake.
check_screens '*-dominate-giant'
check_expect "You sieze control of the hill giant's mind!" \
    "the hill giant was dominated, so MakeCompanion really ran on a CR-7 cost"
check_expect "The hill giant breaks free of your control!" \
    "the corrected rule refused it (the upstream build kept it as a companion)"

# Fault 1: the kobold costs XCR(0)=55, not the upstream max(10,(0+2)^3)=10.
check_screens '*-group-after-kobold'
check_expect "PHD MAGIC   0 / 1" \
    "a charged follower reads exactly its own CR, not one lower"
check_reject "PHD MAGIC   -8 / 1" \
    "the upstream undercharge (XCR 10) is gone"

# Fault 2: the giant is refused, so the pools do not move from the control.
check_screens '*-group-after-giant'
check_expect "PHD MAGIC   0 / 1" \
    "the refused giant is not counted in the magic pool"
check_expect "PHD PARTY   -8 / 3" \
    "and its deficit was not written off; the party pool stays empty"
check_reject "PHD PARTY   7 / 3" \
    "the upstream overflow (giant admitted) is gone"

check_done "companion pools charge their followers at scale and charge a full pool's deficit to the party"
