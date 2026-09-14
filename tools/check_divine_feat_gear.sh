#!/bin/bash
# gate: live
# A divine feat's resistance protects the bearer's CARRIED GEAR (bd inc-w26h).
#
# THE RULE, ruled by the owner under inc-w26h: FT_DIVINE_ARMOUR and
# FT_DIVINE_RESISTANCE protect the bearer's equipment as well as his hit
# points. src/Values.cpp gives both feats one helper, DivineFeatResist, and
# calls it from BOTH Creature::ResistLevel and Creature::GearResistLevel so the
# two halves cannot drift apart.
#
# WHAT THIS CHECK DEFENDS. The gear half. Before inc-w26h, GearResistLevel
# counted only a RESIST stati whose effect carries EF_PROTECTS_ITEMS, and
# neither feat's grant carries an effect id at all, so neither could ever be
# flagged and neither reached a single carried item. The wearer half was never
# in doubt and is not what this check watches.
#
# WHICH FEAT IT MEASURES, AND WHY THE OTHER IS COVERED WITHOUT ITS OWN SESSION.
# This check measures FT_DIVINE_RESISTANCE. Of the five damage types
# FT_DIVINE_ARMOUR covers -- necrotic, holy, lawful, chaotic and unholy -- not
# one has a monster in lib/ that can damage equipment with it: every A_DEQU in
# lib/ deals fire, acid, decay, rust or shatter. Divine Armour therefore has no
# live carrier to strike with, and it rides on two things instead: the helper
# both feats share, which this session exercises, and the static rule in
# tools/equipment_static.py.
#
# THE ARITHMETIC, and it is decisive rather than lucky. The firebat's A_DEQU is
# 1d3 AD_FIRE with NO save DC (lib/mon2.irh:3716) -- the only fire, cold or
# lightning carrier in lib/ with no DC -- so no Reflex roll decides anything,
# and src/Fight.cpp:2122 sets e.ignoreHardness because the warhammer is not
# magical. Iron's fire hardness is 10 and the bypass zeroes it, so the feat's
# grant is the WHOLE of the number on the line. Charisma 18 is the point-buy
# cap, so Creature::Mod returns (18-10)/2 = 4. Item::Damage adds that after the
# bypass (src/Item.cpp:1463) and returns unhurt at :1527 whenever
# hard >= e.vDmg. 1d3 cannot exceed 3, and 4 > 3, so no roll can reach the
# warhammer. Charisma 16 would also hold, because 3 >= 3 returns too, but only
# on the boundary; 18 is a clear point above the largest roll the die has.
#
# HOW THE CHARACTER GETS CHANNELING, which both feats require. src/Skills.cpp
# :4492 grants CHANNELING for Charisma x 2 rounds when a character with any of
# seven divine feats uses Turn Undead. The grant is at :4492 and the turn is
# rolled at :4496, after it, so the attempt need not succeed and NO UNDEAD NEED
# BE PRESENT: the key script turns into an empty room, the game answers
# "Nothing happens", and Channeling appears on the status line all the same.
# Measured 2026-09-11, seed 5: 36 rounds covers the whole session and
# Channeling is on all eight strike screens.
#
# THE ORACLES, all three asserted. Channeling on the status line, so the check
# cannot pass for the wrong reason; the game's own combat-numbers line in
# Item::Damage, which prints the hardness actually used on every landed blow:
#   "Warhammer: 1d3 Fire = 2 vs. 4 (iron) [unhurt]"
# and the warhammer's hit points before and after, because a number on a screen
# is not yet an item that survived. The character sheet is read too, for the
# feat's name and for "Fire 4", so the magnitude is not inferred.
#
# Measured 2026-09-11, seed 5: the sheet reads "Divine Resistance" and
# "Fire 4", 5 of 8 strike screens read "vs. 4 (iron) [unhurt]" (the other three
# are misses, which provoke no retaliation at all), the warhammer is 45/45
# before and after, and no screen reports fire damage to it.
#
# Usage: tools/check_divine_feat_gear.sh [--prove-red]
# THE DECLARED MUTATION takes the DivineFeatResist call out of
# GearResistLevel ONLY, and leaves the one in ResistLevel alone: the character
# must still resist the fire himself, so only the GEAR half moves. That is the
# tree as it stood before inc-w26h.
# PROVED RED: with src/Values.cpp mutated, this check exits 1.
# Exact failing output of the mutated run:
#   |   screens: 8 matching '*-divine-strike-*'
#   |   FAIL  0/8 screens carry: vs. 4 (iron)
#   |         it should prove: the feat's resistance reaches the mundane warhammer
#   |   FAIL  5/8 screens still carry: vs. 0 (iron)
#   |         it should prove: no blow lands on a hardness the bypass emptied
#   |         first: vs. 0 (iron)
#   |   screens: 1 matching '*-divine-after'
#   |   FAIL  0/1 screens carry: It has 45 out of 45 hit
#   |         it should prove: the warhammer is undamaged after eight blows
#   |   screens: 13 matching '*'
#   |   FAIL  5/13 screens still carry: melts
#   |         it should prove: no screen reports fire damage to the warhammer
#   |         first: melts
#   |
#   | FAIL: a divine feat's resistance protects a mundane weapon
# The mutated run rolls the same five values the passing run rolls -- 1, 2, 2,
# 3 and 3 -- but the five lines read "vs. 0 (iron)" and take the whole roll as
# damage. They sum to 11, and the page reads "The Mildly Melted Uncursed
# Warhammer ... 34 out of 45 hit". The character sheet still reads "Fire 4" in
# both runs, which is the wearer half staying exactly where it was.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
check_mutation src/Values.cpp \
'    if (DivineFeatResist(this,DType,divine))
      best = max(best,divine);' \
'    if (false && DivineFeatResist(this,DType,divine))
      best = max(best,divine);'

check_run tools/keys/divine-feat-gear.keys 5
check_screens '*-divine-before'
check_expect "The Uncursed Warhammer ('" "the character wields an ordinary iron warhammer"
check_expect "It has 45 out of 45 hit" "the warhammer starts undamaged"
check_screens '*-divine-channel'
check_expect "Channeling" "turning undead put Channeling on the status line"
check_screens '*-divine-sheet'
check_expect "Divine Resistance" "the character really holds the feat"
check_expect "Fire 4" "the feat's fire resistance is on the character, at 4"
check_screens '*-divine-strike-*'
check_expect_all "Channeling" "Channeling is still up when every blow lands"
check_expect "vs. 4 (iron)" "the feat's resistance reaches the mundane warhammer"
check_reject "vs. 0 (iron)" "no blow lands on a hardness the bypass emptied"
check_screens '*-divine-after'
check_expect "It has 45 out of 45 hit" "the warhammer is undamaged after eight blows"
check_screens
check_reject "melts" "no screen reports fire damage to the warhammer"
check_done "a divine feat's resistance protects a mundane weapon"
