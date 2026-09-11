#!/bin/bash
# gate: live
# Do tanglefoot strands catch the MOUNT and leave the rider free? (bd inc-lxvv)
#
# THE RULE: a mounted character who rides through tanglefoot strands must not
# become stuck himself; his mount must. The mount rolls the reflex save, so the
# mount is what the failed save catches. lib/alchemy.irh used to send the
# consequence to the rider instead -- ThrowDmg(...,EActor,EActor) -- so the
# player stood in the strands with "Stuck" on his own status line while the
# horse under him walked free.
#
# THE ORACLE is wizard mode's "Examine Player Data", which prints the rider's
# stati list and then, under a "----MOUNT----" banner, the mount's
# (src/Debug.cpp:1712-1716). It names both creatures in one window, which is
# what the original report used. tools/keys/tanglefoot-mount.keys explains the
# ride, the two scroll depths and why the strands catch a creature LEAVING them
# rather than one entering.
#
# PROVED RED on 2026-09-11 (docs/VERIFICATION.md step 2). The mutation is the
# one declared below -- lib/alchemy.irh's mounted ThrowDmg sent back to
# EActor,EActor, which is exactly the edit dc6496a made, reversed -- the module
# rebuilt from lib/, and the check re-run. Four assertions flipped, and between
# them they are the original report:
#
#   FAIL  0/1 screens carry: STUCK from SS ATTK
#         it should prove: THE RULE, positive half: the mount carries STUCK
#   FAIL  1/1 screens still carry: STUCK
#         it should prove: THE RULE, negative half: no STUCK anywhere in the
#         rider's stati
#   FAIL  0/1 screens carry: Keeper seems to be stuck.
#         it should prove: the message line names the mount as the creature
#         the strands caught
#   FAIL  1/1 screens still carry: Stuck
#         it should prove: and no status line on that screen says the rider is
#         Stuck
#
#   PROVED RED: with lib/alchemy.irh mutated, this check exits 1.
#
# Usage: tools/check_tanglefoot_mount.sh              0 pass, 1 fail, 2 no measurement
#        tools/check_tanglefoot_mount.sh --prove-red  break the fix and prove it goes red
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# Undo exactly what dc6496a did: send the AD_STUK back to the rider while the
# mount keeps rolling the save. That is the defect this check was written for.
check_mutation lib/alchemy.irh \
    '"tanglefoot strands",mount,mount' \
    '"tanglefoot strands",EActor,EActor'

check_run tools/keys/tanglefoot-mount.keys 4

# --- the mount is the one that is stuck -----------------------------------
check_screens '*-mount-stati'
check_expect "----MOUNT----" \
    "the dump reached the mount's own section"
check_expect "horse named Keeper" \
    "and that section is the sacred mount, not some other creature"
check_expect "STUCK from SS ATTK" \
    "THE RULE, positive half: the mount carries STUCK"

# --- the rider is not ------------------------------------------------------
# "Stati (" and "Inventory:" bracket the rider's list, so both being on screen
# says the list is whole. Without that, an absent STUCK could just mean the
# line scrolled past the bottom edge.
check_screens '*-rider-stati'
check_expect "Stati (" \
    "the rider's stati list drew"
check_expect "MOUNTED from SS MISC" \
    "and it is his list: it names Keeper as the mount he is on"
check_expect "Inventory:" \
    "and it drew whole, so an absent STUCK is absence and not a cut-off screen"
check_reject "STUCK" \
    "THE RULE, negative half: no STUCK anywhere in the rider's stati"

# --- and the player is told so, in his own words ---------------------------
check_screens '*-crossed'
check_expect "Keeper seems to be stuck." \
    "the message line names the mount as the creature the strands caught"
check_reject "Stuck" \
    "and no status line on that screen says the rider is Stuck"

check_done "the strands caught the mount and left the rider free"
