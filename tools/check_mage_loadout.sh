#!/bin/bash
# gate: live
# Does a Mage's spell checklist change his loadout only at the next full rest?
# (bd inc-j5yo)
#
# THE CLAIM. The Learn Spells checklist shows level headers and the memorized
# spells marked; marking past a full level is refused; a class-grant spell
# cannot be unmarked; Esc discards; Enter on a changed arcane selection says it
# "takes effect at your next full rest", and until that rest the dropped spell
# is still castable and the new one is not. A completed rest then applies the
# selection: with the spellbooks in the pack the new spell is memorized and the
# dropped one is gone; with the books dropped the rest memorizes nothing, names
# the spells it could not memorize, and a second rest after picking the books up
# memorizes them.
#
# THE ORACLE is the screen dumps of tools/keys/mage-loadout-rest.keys (the
# checklist, the message log, and the cast menu, which lists exactly the spells
# with SP_KNOWN). It runs on the frozen Orc Mage fixture, whose save migrates on
# load (see tools/check_spellflag_migrate.sh). The expected spell names are the
# fixture's own (tools/fixtures/chars/orc-mage-seed1-opt0822.sheet.txt).
#
# PROVED RED with --prove-red: the mutation disables the ApplySpellSelection()
# call in Player::Rest (src/Player.cpp). The rest then applies nothing, so the
# post-rest cast menus keep Convulsion, never gain Endure Cold, and the
# "could not memorize" message is missing; the check exits 1.
#
# Usage: tools/check_mage_loadout.sh [--prove-red]
#   0 every expectation holds   1 one fails   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/orc-mage-seed1-opt0822.sav
SEED=1

check_mutation src/Player.cpp \
'        ApplySpellSelection();' \
'        ; /* mutation: the rest no longer applies the selection */'

[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE to load."
export INCURSION_LOAD="$FIXTURE"

check_run tools/keys/mage-loadout-rest.keys "$SEED"

# a. the checklist opens with level headers and the memorized spells marked
check_screens '*-open'
check_expect "Level 1 - 3 of 3 slots"        "a: a level header with live slot counts"
check_expect "[*] Alarm (memorized)"         "a: Alarm is marked and memorized"
check_expect "[*] Burning Hands (memorized)" "a: Burning Hands is marked and memorized"
check_expect "[*] Convulsion (memorized)"    "a: Convulsion is marked and memorized"

# d. marking past a full level is refused
check_screens '*-refused'
check_expect "Level 1 has no free slot."     "d: marking in a full level is refused"

# b. the swap, and the specialty spell cannot be unmarked
check_screens '*-swapped'
check_expect "[ ] Convulsion (memorized)"    "b: Convulsion is unmarked"
check_expect "[*] Endure Cold"               "b: Endure Cold is marked"
check_screens '*-locked'
check_expect "This spell is a class grant and stays." "d: unmarking a specialty spell is refused"
check_expect "[#] Magic Missile (locked)"    "d: Magic Missile is still locked and marked"

# b. the message, and the loadout has not changed yet
check_screens '*-msgs-enter'
check_expect "Your selection takes effect at your next full rest." "b: the player is told"
check_screens '*-cast-before'
check_expect "] Convulsion"                 "b: the dropped spell is still castable"
check_expect "] Magic Missile"                "b: the cast menu is the spell list (control)"
check_reject "] Endure Cold"                  "b: the new spell is not castable yet"

# d. Esc discards
check_screens '*-esc-pre'
check_expect "[ ] Alarm (memorized)"         "d: the change is visible before Esc"
check_screens '*-esc-post'
check_expect "[*] Alarm (memorized)"         "d: Esc discarded the change"

# d. the books are gone: pending rows say so
check_screens '*-rows-nobook'
check_expect "[*] Endure Cold (no book)"     "d: the pending spell shows (no book)"

# d. the rest with no books memorizes nothing and names the spells
check_screens '*-msgs-rest1'
check_expect "could not memorize: Alarm, Burning" "d: the rest names the spells it could not memorize"
check_expect "Endure Cold."                       "d: Endure Cold is among them"
check_screens '*-cast-nobook'
check_expect "] Magic Missile"                "d: the cast menu is the spell list (control)"
check_reject "] Endure Cold"                  "d: no book, so Endure Cold is not memorized"
check_reject "] Convulsion"                   "c: the rest forgot the unpicked Convulsion"

# c, d. the books are back and the second rest applies the selection
check_screens '*-msgs-rest2'
check_expect "You awaken feeling well rested" "c: the second rest completed"
check_screens '*-cast-after'
check_expect "] Endure Cold"             "c: the new spell is castable after the rest"
check_expect "] Burning Hands"               "d: a spell memorized after the books came back"
check_expect "] Alarm"                       "d: a spell memorized after the books came back"
check_expect "] Magic Missile"                "c: the grant stays"
check_reject "] Convulsion"                   "c: the dropped spell is not castable after the rest"

check_done "the loadout changes only at a full rest, and needs the spellbook"
