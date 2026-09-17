#!/bin/bash
# gate: live
# Does an illusion's declared IL_IMPROVED flag decide who pierces it, rather
# than the parity of its save DC? (bd inc-pu6v.43)
#
# THE DEFECT. Thing::isRealTo read the flag out of Status::Val:
#
#     if (!(s->Val & IL_IMPROVED))        /* src/Creature.cpp:2278 */
#
# Status::Val on an ILLUSION stati is the SAVE DC. Every grant site fills it
# from e.saveDC and Thing::DisbeliefCheck spends it as a DC. The declared flags
# live on the effect resource's yval, which Thing::getIllusionFlags returns and
# which the illusory-TERRAIN path already read correctly (src/Status.cpp:1695).
# IL_IMPROVED is 2, so the old line tested bit 1 of the DC: an illusion counted
# as improved at DC 2, 3, 6, 7, 10, 11 and so on, whatever its spell declared.
#
# An illusion the engine calls ordinary is pierced with NO saving throw by a
# watcher with sharpened senses, scent, blindsight or tremorsense
# (src/Creature.cpp:2278-2285), so the defect inverted that ruling on half of
# all illusions.
#
# WHAT THIS CHECK MEASURES. A frozen elf casts four illusion spells that sit one
# level apart. Their save DCs therefore rise by exactly 1 per rung while their
# declared flags alternate, so any code that reads the flag out of the DC must
# disagree with the declaration on some rung:
#
#   spell                       level  DC  declared yval            improved?
#   Phantasmal Force              1    15  0                        no
#   Improved Phantasmal Force     2    16  IL_IMPROVED              YES
#   Spectral Force                3    17  IL_SPECTRAL              no
#   Improved Spectral Force       4    18  IL_SPECTRAL|IL_IMPROVED  YES
#
# Measured on 2026-09-17, before the fix: rungs 1 and 2 came out INVERTED --
# Phantasmal Force, which declares no flags and whose own description says it is
# "automatically disbelieved by any creature with tremorsense, sharpened senses,
# scent or blindsight", resisted the elf; Improved Phantasmal Force, which
# declares IL_IMPROVED and whose description says the opposite, did not. Rungs 3
# and 4 were right by arithmetic accident. After the fix all four match their
# declaration.
#
# THE ORACLE is Creature::PickUp (src/Inv.cpp:496-505), which prints one of two
# lines and never both:
#
#   pierced      -> "You can't pick up an illusionary item."
#   not pierced  -> "...your hand passes through it, and it winks out of
#                    existence!"
#
# The caster is the watcher, and that is sound here: the illusory-ITEM arm of
# Magic::Illusion grants the caster no DISBELIEVED stati, unlike the
# illusory-CREATURE arm, so the elf gets a genuine isRealTo verdict on an
# illusion he cast himself.
#
# THE ELF IS THE POINT. The elf monster template is one of only three player
# templates that grant CA_SHARP_SENSES -- elf, drow and grey elf
# (lib/races.irh:952, lib/races.irh:1229, lib/subraces.irh:484). No dwarf,
# lizardfolk, kobold or dragonkin does; a first draft of this check used a dwarf
# and measured nothing, because HasAbility(CA_SHARP_SENSES) was false all four
# times.
#
# THE CHARACTER IS FROZEN, not generated. An rID is a position, so one resource
# added to lib/ would hand a regenerated elf different attributes and therefore
# different DCs. See tools/fixtures/README.md.
#
# Usage: tools/check_illusion_flags.sh [--prove-red]

. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/elf-mage-illusions-seed1.sav

# Put the defect back: read the flag out of the save DC again.
check_mutation src/Creature.cpp \
    'if (!(getIllusionFlags() & IL_IMPROVED)) {' \
    'if (!(s->Val & IL_IMPROVED)) {'

check_run tools/keys/illusion-flags.keys 1

check_screens '*-il-a-plain'
check_expect "can't pick up an illusionary item" \
    "Phantasmal Force declares no flags, so sharp senses pierce it"
check_reject "winks out of existence"

check_screens '*-il-b-improved'
check_expect "winks out of existence" \
    "Improved Phantasmal Force declares IL_IMPROVED, so sharp senses do not"
check_reject "can't pick up an illusionary item"

check_screens '*-il-c-spectral'
check_expect "can't pick up an illusionary item" \
    "Spectral Force declares IL_SPECTRAL but not IL_IMPROVED"
check_reject "winks out of existence"

check_screens '*-il-d-spectral-improved'
check_expect "winks out of existence" \
    "Improved Spectral Force declares IL_IMPROVED"
check_reject "can't pick up an illusionary item"

check_done "the declared IL_IMPROVED flag decides who pierces an illusion, on all four rungs"
