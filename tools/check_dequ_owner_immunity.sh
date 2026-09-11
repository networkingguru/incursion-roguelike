#!/bin/bash
# gate: live
# Does the owner's own immunity still shield his gear? (bd inc-w26h)
#
# THE RULE. Item::Damage used to return before it did anything at all -- no
# damage, no message -- when the item's OWNER was immune to the damage type:
#
#     if (owner)
#         if (e.DType == AD_SOAK || e.DType == AD_RUST || e.DType == AD_DCAY)
#             if (owner->ResistLevel(e.DType) == -1)
#                 return DONE;
#
# so a character who could not be rusted himself carried a sword that could not
# be rusted either. The owner's defences no longer reach his gear at all: the
# ruling is that owner resistance must not apply to ANY item.
#
# THE SUBJECT. "Rust;gauntlet" (lib/m_items.irh:4348) grants IMMUNITY to
# exactly the three damage types that block named, so wearing it makes
# ResistLevel(AD_RUST) return -1, which is the sentinel the old code tested.
# Nothing else reachable from wizard mode gives a character a true immunity:
# the Ring of Elemental Command grants a resistance of 10, which is a magnitude
# and not the sentinel. The run dumps the character sheet's Resistances page as
# evidence that the immunity is really on him.
#
# The small mud elemental's A_DEQU is 1d6 AD_RUST (lib/mon4.irh:2396) and iron
# has a hardness of 0 against rust, so every retaliation that lands does its
# whole roll. The old rule leaves the weapon untouched; the new one rusts it.
# That is a difference in kind and not in degree, which is what makes this the
# easiest of these rules to read off a screen.
#
# THE ORACLE is the maul's own description page, reached from the inventory by
# selecting the Weapon Hand and pressing 'x'. Measured on the current tree,
# seed 5:
#
#   before  The Uncursed Maul ('v')                 It has 262 out of 262 hit
#   after   The Mildly Rusted Uncursed Maul ('v')   It has 258 out of 262 hit
#
# A maul because it is the heaviest ordinary weapon in lib, 262 hit points, so
# no run of retaliations can destroy it and leave no page to read.
#
# WHAT THIS CHECK DOES NOT COVER. The same edit also removed
# "hard += owner->ResistLevel(e.DType)", which added a RESISTANCE short of
# immunity to the item's own hardness. That half changes a number rather than a
# kind, and tools/check_item_owner_resist.sh guards it in the source.
#
# PROVED RED on 2026-09-10 by putting the old immunity gate back. The inner run
# printed:
#
#   |   FAIL  0/5 screens carry: Your maul rusts
#   |         it should prove: a retaliation reached the maul and rusted it
#   |   FAIL  0/1 screens carry: Rusted Uncursed Maul
#   |         it should prove: the maul is rusted after five blows
#   |   FAIL  1/1 screens still carry: It has 262 out of 262 hit
#   |         it should prove: the maul lost hit points
#   | FAIL: an immune character's weapon rusts like anybody else's
#   PROVED RED: with src/Item.cpp mutated, this check exits 1.
#
# Usage: tools/check_dequ_owner_immunity.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Item.cpp \
'    Creature *owner = Owner();
    /* inc-w26h: item defences do not inherit owner resistances or immunities. */
    hard = Hardness(e.DType);' \
'    Creature *owner = Owner();
    if (owner)
        if (e.DType == AD_SOAK || e.DType == AD_RUST || e.DType == AD_DCAY)
            if (owner->ResistLevel(e.DType) == -1)
                return DONE;
    hard = Hardness(e.DType);'

check_run tools/keys/dequ-owner-immunity.keys 5

check_screens '*-immune-sheet'
check_expect "Complete Immunities:" \
    "the character sheet lists what he cannot be hurt by"
check_expect "Rusting" \
    "and rust is on that list, so ResistLevel(AD_RUST) is the -1 sentinel"

check_screens '*-immune-strike-*'
check_expect "Your maul rusts" \
    "a retaliation reached the maul and rusted it"

check_screens '*-immune-before'
check_expect "The Uncursed Maul ('" \
    "the character wields an ordinary iron maul"
check_expect "It has 262 out of 262 hit" \
    "and it is undamaged before the first blow"

check_screens '*-immune-after'
check_expect "Rusted Uncursed Maul" \
    "the maul is rusted after five blows"
check_reject "It has 262 out of 262 hit" \
    "the maul lost hit points"

check_done "an immune character's weapon rusts like anybody else's"
