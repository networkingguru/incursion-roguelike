#!/bin/bash
# gate: live
# Does taking Intensive Study's caster-level study through the ordinary
# level-up feat menu raise the character sheet's Spell Slots line to the
# spellcasting chart at the new effective caster level? bd inc-ngku.
#
# THE ROUTE is gameplay, not a probe: tools/keys/intensive-study-caster-sheet.keys
# loads tools/fixtures/chars/prestige-geomancy-seed1-opt0822.sav (Ferris, a
# single-class Bard 7 whose Spellcasting ability sits at 3rd, well behind the
# 4/5-of-character-level cap Character::getEligableStudies() checks, so
# Intensive Study's caster-level study is eligible), levels him up twice
# through the sheet's ordinary G command (Player::AdvanceLevel), and takes
# Intensive Study on the second level-up -- src/Create.cpp:3143's
# FT_INTENSIVE_STUDY case finds only the one eligible study and applies it
# without a further menu. The key script's own header has the file:line
# detail for each step.
#
# THE MUTATION is the two lines this check watches, the call
# Player::GainFeat makes from the study site (src/Create.cpp, the
# ChosenStudy label inside FT_INTENSIVE_STUDY): without them, IntStudy[choice]
# still records the study but no slot follows it, which is the defect
# inc-ngku fixed. `--prove-red` cuts exactly these two lines, rebuilds, and
# proves the assertion below goes red.
#
# THE ORACLE is the sheet's own Spell Slots line, read off the screen after
# the study. Bard 7's line is "3rd  2+5 (6) / 1+1 (2)"; two ordinary levels
# (7->8->9, no study effect) raise the raw chart, and the study's effective-
# level bump must add the third slot tier, giving exactly the line this check
# asserts. Fixed: that third tier is present. Unfixed: the line stops after
# the second tier, because the study raised AbilityLevel(CA_SPELLCASTING) for
# every OTHER purpose but no chart re-read followed it for this one.
#
# Usage: tools/check_intensive_study_play.sh            (0 pass, 1 fail, 2 inconclusive)
#        tools/check_intensive_study_play.sh --prove-red (docs/VERIFICATION.md step 2)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22-freeadv.dat

check_mutation src/Create.cpp \
'            if (choice == STUDY_CASTING)
                RaiseSpellSlotsToChart();
' \
''

export INCURSION_LOAD=tools/fixtures/chars/prestige-geomancy-seed1-opt0822.sav

check_run tools/keys/intensive-study-caster-sheet.keys 1

check_screens '*-sheet-before*'
check_expect "Class  Bard 7" "the run started from the frozen Bard 7 fixture"

check_screens '*-sheet-after*'
check_expect "Class  Bard 9" "two G level-ups landed (7 -> 8 -> 9)"
check_expect "Spell Slots    5th  3+5 (7) / 2+2 (4) / 1+1 (2)" \
    "Intensive Study's caster-level study raised Spell Slots to the chart at the new effective caster level"

check_done "Intensive Study raises Spell Slots to match the new effective caster level, read off the character sheet"
