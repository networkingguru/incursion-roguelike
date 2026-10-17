#!/bin/bash
# gate: live
# Can a Mage cast a memorized arcane spell with no spellbook in his pack, while a
# Priest with no holy symbol still cannot cast a divine one? (bd inc-q04n)
#
# THE CLAIM. Creature::Cast (src/Magic.cpp) no longer refuses an arcane spell
# for lack of a spellbook: the spell takes effect and spends mana. A divine
# spell still needs a holy symbol equipped, and still says so.
#
# THE ORACLE (A) is tools/keys/mage-cast-nobook.keys on the frozen Orc Mage
# fixture: he drops all six books, opens the cast menu and casts Shield. Shield
# is a class grant, needs no target, and costs 5 mana, so a real cast shows both
# its own effect message and a drop in the mana on the status line. The refusal
# "You don't have a spellbook with that spell" MUST be absent AND the spell's
# own message MUST be present: absence alone never passes. A run with no dump
# exits 2.
#
# THE CONTROL (B) is tools/keys/priest-cast-nosymbol.keys on the frozen Orc
# Priest fixture: he drops his holy symbol and casts Bless. The refusal "You
# need to have a holy symbol equipped to cast divine spells." MUST appear. B
# reads the same before and after the change; it is red only if the change
# loosens the divine rule too.
#
# EXPECTED: red on a tree that still requires the book (A fails), green after.
# --prove-red (valid only on a green tree) casts Magic Missile instead of Shield,
# so the Shield message is missing and the check exits 1.
#
# Usage: tools/check_mage_cast_nobook.sh [--prove-red]
#   0 every expectation holds   1 one fails   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
MAGE=tools/fixtures/chars/orc-mage-seed1-opt0822.sav
PRIEST=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav
SEED=1

check_mutation tools/keys/mage-cast-nobook.keys \
'@choose "(arc)Shield"' \
'@choose "(arc)Magic Missile"'

[ -f "$MAGE" ]   || _check_die 2 "no $MAGE to load."
[ -f "$PRIEST" ] || _check_die 2 "no $PRIEST to load."

# A. the Mage, books dropped
export INCURSION_LOAD="$MAGE"
check_run tools/keys/mage-cast-nobook.keys "$SEED"

check_screens '*-cast-menu'
check_expect "] (arc)Shield"                  "A: Shield is in the cast menu (the run got there)"
check_screens '*-after-cast'
check_expect "Mana:"                          "A: the status line is on the dump"
check_screens '*-after-cast'
check_reject "You don't have a spellbook with that spell" "A: the cast was not refused for the book"
check_screens '*-msgs'
check_reject "You don't have a spellbook with that spell" "A: the message log has no book refusal"
check_expect "A shield-sized wall of force appears by your arm." "A: the log shows the spell was cast"
check_screens '*-after-cast'
check_expect "A shield-sized wall of force appears by your arm." "A: the screen shows the spell was cast"
check_reject "Mana:73/73"                     "A: mana was spent by the cast"

# B. the Priest, symbol dropped
export INCURSION_LOAD="$PRIEST"
check_run tools/keys/priest-cast-nosymbol.keys "$SEED"

check_screens '*-symbol-gone'
check_expect ")Neck         :Empty"            "B: the holy symbol is out of the Neck slot"
check_screens '*-after-cast'
check_expect "You need to have a holy symbol equipped to cast divine spells." "B: the divine cast is still refused"

check_done "an arcane spell casts with no spellbook; a divine spell still needs its holy symbol"
