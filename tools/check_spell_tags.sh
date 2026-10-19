#!/bin/bash
# gate: live
# inc-4999 phase 5: does every player-facing spell list lead each spell row with
# its short source tag, before the name?
#
# WHAT IS BEING GUARDED. A spell is HELD from one or more sources
# (SP_ARCANE/SP_DIVINE/SP_PRIMAL/SP_BARDIC). Phase 4a gave the Spell Manager and
# the Learn Spell checklist one row per (spell, source), told apart by a
# " (Arcane)"/" (Divine)" SUFFIX, and only when a spell had two rows. Phase 5
# (owner ruling, bead inc-4999 rule 5) puts a SHORT tag BEFORE the name on EVERY
# row that has a source -- "(arc)", "(div)", "(pri)", "(brd)", "(sor)" -- so a
# long name cannot hide it. The one helper is Creature.h's SpellSrcTagName
# (beside the SpellVersion* helpers); a row with no source keeps no tag.
#
# THE CHARACTER is tools/fixtures/chars/human-priest-mage-dual-seed4-gate.sav:
# Kethad, Priest 1 / Mage 1, holding Protection from Evil from BOTH sources
# (arcane=1 divine=1), saved in wizard mode at depth 2.
#
# THE ORACLES:
#   A (cast menu). The Spell Manager ('m') shows the two Protection from Evil
#     versions as "(arc)Protection from E" and "(div)Protection from E". The
#     name column is cut to 22 characters (src/Managers.cpp) and the tag leads,
#     so the arcane row also proves the tag survives the cut on a long name:
#     tag+name is 25 characters, the name's tail is lost, the tag is not.
#   B (Learn Spells). The Learn Spells table (Term::LearnTable, src/TextTerm.cpp)
#     shows each held version of Protection from Evil as a table row carrying its
#     source in the Source column, rather than a tag before the name: one row
#     reads "Protection from Evil   Arcane" and the other
#     "Protection from Evil   Divine". A row with no source still keeps no tag
#     (there is no Source column entry to read either way).
#   C (character sheet). ESC leaves the sheet, then ESC opens the System Menu
#     and 'b' is Save and Continue. INCURSION_CHAR_PROBE=1 makes Game::SaveGame
#     write logs/charprobe.txt -- the character sheet's full "Known Spells"
#     dump (TextTerm::CreateCharDump, src/Sheet.cpp) -- whose two Protection
#     from Evil lines each carry their own tag and rating. The file is copied
#     beside the screen dumps so check_expect reads it like any other screen.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation makes
# Creature.h's SpellSrcTagName return "" for the arcane case, so every arcane
# row loses its tag; the "(arc)Protection from" assertions then fail and the
# check exits 1.
#
# Usage: tools/check_spell_tags.sh [--prove-red]
#   0 every expectation holds   1 one fails   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/human-priest-mage-dual-seed4-gate.sav
KEYS=tools/keys/spell-tags.keys
SEED=4

check_mutation inc/Creature.h \
'        case SP_ARCANE: return "(arc)";' \
'        case SP_ARCANE: return "";'

[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE to load."
[ -f "$KEYS" ]    || _check_die 2 "no $KEYS to run."

export INCURSION_LOAD="$FIXTURE"
export INCURSION_CHAR_PROBE=1
check_run "$KEYS" "$SEED"

# A. the cast menu leads each held version with its tag, before the name.
check_screens '*-cast-menu'
check_expect "(arc)Protection from" "A: the arcane cast-menu row leads with its tag"
check_expect "(div)Protection from" "A: the divine cast-menu row leads with its tag"

# A2. a long name: tag+name exceeds the 22-character column, so the tag must
# survive the cut. "(arc)Protection from E" is exactly what the 22-char cut
# leaves -- the tag is intact and the name's tail is gone.
check_expect "(arc)Protection from E" \
    "A2: the tag survives the 22-character name column on a long name"

# B. the Learn Spells table names each held version's source in its Source
# column (the table replaced the old "(arc)"/"(div)"-prefixed checklist rows).
check_screens '*-learn-spells'
check_expect "Protection from Evil   Arcane" "B: the arcane table row names its source"
check_expect "Protection from Evil   Divine" "B: the divine table row names its source"

# C. the character sheet's Known Spells list leads each held version with its
# own tag (and rates that version). charprobe.txt is that whole sheet.
PROBE="$CHECK_RUN/logs/charprobe.txt"
[ -f "$PROBE" ] || _check_die 2 \
    "no logs/charprobe.txt -- INCURSION_CHAR_PROBE=1 should have made" \
    "Game::SaveGame write one. See $CHECK_RUN."
cp "$PROBE" "$CHECK_RUN/logs/screens/charprobe-sheet.txt"
check_screens 'charprobe-sheet'
check_expect "(arc)Protection from Evil" "C: the sheet's Known Spells has the arcane tagged line"
check_expect "(div)Protection from Evil" "C: the sheet's Known Spells has the divine tagged line"

check_done "every spell row with a source leads with its tag, and the tag survives a long-name cut"
