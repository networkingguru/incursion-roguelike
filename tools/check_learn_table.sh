#!/bin/bash
# gate: live
# inc-g045 phase 4: does the Learn Spells table (src/TextTerm.cpp) draw its
# level pages in the right order, does Tab walk them and wrap, does Enter draw
# the summary box with a clear interior and no table text behind it, does ESC
# go back to the table, and does a confirmed selection take effect?
#
# WHAT IS BEING GUARDED. Phase 1 built Term::LearnTable, a full-screen table
# with one page per spell level and a "[*]"/"[ ]" pick column; phase 2 wired
# Player::LearnSpell (src/Create.cpp) to it and ordered a level's rows by
# source (Arcane, then Divine), then by name, so the row order is deterministic.
# Phase 3 added a summary box on Enter: it lists what will change at the next
# full rest, and Enter on the box confirms, ESC returns to the table. This
# phase fixes one defect the phase 3 run found (logs/inc-g045-p3): the box was
# drawn over the table WITHOUT blanking its interior, so table text showed
# through its walls. The fix blanks every cell inside the walls first.
#
# THE CHARACTER is tools/fixtures/chars/human-priest-mage-dual-seed4-gate.sav:
# Kethad, Priest 1 / Mage 1, saved in wizard mode at depth 2, already rested.
# His table has ONE page, Level 1 (3 of 3 slots used); his level 1 spells come
# from both sources, so the Arcane rows must all sit above the Divine ones.
#
# THE ORACLES (learn-table-check.keys and learn-table-needs-book.keys, seed 4):
#   T1 (table). The level 1 page's title, column header, a "[*]" Memorized
#     Arcane row (Protection from Evil), a blank-Pick "Class grant" row (Mage
#     Armour), and Arcane-before-Divine order by the rows' line numbers.
#   T2 (Tab). Tab keeps the title on Level 1 -- the only level the fixture has
#     -- and a second Tab still reads Level 1, so the page wraps rather than
#     running off the end.
#   T3 (summary box). Enter draws a box naming the changes, and the box's
#     interior is clear: the line carrying "At your next full rest:" must NOT
#     also carry a table school like "Abjuration". That is the defect this
#     phase fixes; before it, the run's screenshot showed
#     "|cAt your next full rest:Abjuration      5     |".
#   T4 (ESC from box). ESC returns to the table, marks intact.
#   T5 (confirm took effect). After the confirming Enter, reopening the table
#     shows Endure Cold ending "Learn at rest" and the Arcane Protection from
#     Evil ending "Forget at rest".
#   T6 (no change, no box). Enter with no toggle opens no box, and the screen
#     that follows is the character sheet, not the box.
#   T7 (missing book). In a fresh fixture run, the held Arcane Protection
#     from Evil starts [*] Memorized; dropping Mystic Aegis and reopening
#     shows [*] Needs book, fully rendered. Toggling shows Forget at rest.
#     The held Divine row remains [*] Memorized throughout.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation makes
# the Enter case's "did a non-locked row change?" test always find no change
# (src/TextTerm.cpp), so Enter never draws the box; T3's assertions then find
# no box and the check exits 1.
#
# The sort order is also shown to be load-bearing, by a manual mutation NOT
# kept here: making the row sort name-only (src/Create.cpp, LearnSpell's
# insertion sort, `int sr = LearnSrcRank(...) - ...` -> `int sr = 0;`) puts the
# Divine rows among the Arcane ones and T1's Arcane-before-Divine assertion
# fails.
#
# T7 PROVED RED by manual mutation (2026-10-19): in src/Create.cpp,
# replace `r->StatusMarked = noBook ? "Needs book" : "Memorized";` with
# `r->StatusMarked = "Memorized";`, rebuild with
# `BACKEND=posix ./build_macos.sh`, then run tools/check_learn_table.sh.
# Exit 1: only T7's marked Needs book assertion fails; T1..T6 and T7's
# unmark/Divine controls pass. Restoring the expression and rebuilding gives
# exit 0. Evidence: logs/inc-g045-needs-book/{red,green-final}.log.
#
# Usage: tools/check_learn_table.sh [--prove-red]
#   0 every expectation holds   1 one fails   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/human-priest-mage-dual-seed4-gate.sav
KEYS=tools/keys/learn-table-check.keys
SEED=4

# --prove-red: make the "did a row change?" test always say no, so Enter never
# draws the summary box and T3 fails.
check_mutation src/TextTerm.cpp \
'                        changing = true;' \
'                        changing = false;'

[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE to load."
[ -f "$KEYS" ]    || _check_die 2 "no $KEYS to run."

export INCURSION_LOAD="$FIXTURE"
check_run "$KEYS" "$SEED"

# One chosen screen, and one predicate over it. check_expect is fixed-string
# presence; the table's order, its line-ending statuses and the box's clear
# interior need the row's line, so they run their own grep and record the
# verdict through _lt_assert.
#
# check_screens sets CHECK_SCREENS in THIS shell, so it must not be called
# inside a command substitution: a $(...) runs in a subshell and the array it
# fills is thrown away, which is what made the first draft assert against no
# screens at all. _lt_screen fills CHECK_SCREENS and leaves the one path in $F.
F=""
_lt_screen() { # <glob> -> sets F to the single matching screen's path
    check_screens "$1"
    F="${CHECK_SCREENS[0]}"
}

_lt_assert() { # <ok 0|1> <description>
    if [ "$1" -eq 0 ]; then
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
        printf '  ok    %s\n' "$2"
    else
        printf '  FAIL  %s\n' "$2"
        CHECK_FAIL=1
    fi
}

# T1. The fixed level 1 page.
_lt_screen '*-t1-table'; f="$F"
check_expect "Learn Spells: Level 1 (3 of 3 slots used)" "T1: the title names level 1 and 3 of 3 slots"
check_expect "Pick Spell                  Source  School" "T1: the column header"

# a "[*]" Pick row that is Arcane and Memorized.
grep -F '[*]  Protection from Evil   Arcane' "$f" | grep -qF -- 'Memorized'
_lt_assert $? "T1: the arcane Protection from Evil row is [*] and Memorized"

# a blank Pick cell row whose status is Class grant (Mage Armour, Arcane).
grep -F 'Mage Armour' "$f" | grep -qF -- 'Class grant' \
    && ! grep -F 'Mage Armour' "$f" | grep -qE '\[[ *]\]'
_lt_assert $? "T1: Mage Armour has a blank Pick cell and Status 'Class grant'"

# every Arcane row precedes every Divine row: last Arcane line < first Divine.
lt_a=$(grep -nF 'Arcane  ' "$f" | tail -1 | cut -d: -f1)
lt_d=$(grep -nF 'Divine  ' "$f" | head -1 | cut -d: -f1)
[ -n "$lt_a" ] && [ -n "$lt_d" ] && [ "$lt_a" -lt "$lt_d" ]
_lt_assert $? "T1: every Arcane row (last line $lt_a) is above every Divine row (first line $lt_d)"

# T2. Tab stays on level 1 and wraps.
_lt_screen '*-t2-tab'; f="$F"
check_expect "Learn Spells: Level 1" "T2: after Tab the title still names level 1 (the fixture's only level)"
_lt_screen '*-t2-tab2'; f="$F"
check_expect "Learn Spells: Level 1" "T2: after a second Tab the title names level 1 again (wrap)"

# T3. The summary box names the changes and has a clear interior.
_lt_screen '*-t3-summary'; f="$F"
check_expect "At your next full rest:" "T3: the box opens with the rest heading"
check_expect "Learn:   Endure Cold (Arcane, L1)" "T3: the box lists Endure Cold as a learn"
check_expect "Forget:  Protection from Evil (Arcane, L1)" "T3: the box lists the arcane Protection from Evil as a forget"
! grep -F 'At your next full rest:' "$f" | grep -qF -- 'Abjuration'
_lt_assert $? "T3: the box interior is blank -- its rest line carries no table text"

# T4. ESC returns to the table, marks as they were.
_lt_screen '*-t4-table-back'; f="$F"
check_expect "[*]  Endure Cold" "T4: the table is back with Endure Cold marked"
check_expect "[ ]  Protection from Evil   Arcane" "T4: the arcane Protection from Evil is unmarked again"

# T5. The confirming Enter took effect: the reopened table reflects it.
_lt_screen '*-t5-reopened'; f="$F"
check_expect "Learn Spells: Level 1" "T5: the table reopened on level 1"
grep -F '[*]  Endure Cold' "$f" | grep -qF -- 'Learn at rest'
_lt_assert $? "T5: Endure Cold's row ends 'Learn at rest'"
grep -F '[ ]  Protection from Evil   Arcane' "$f" | grep -qF -- 'Forget at rest'
_lt_assert $? "T5: the arcane Protection from Evil's row ends 'Forget at rest'"

# T6. Enter with no toggle draws no box; the character sheet follows.
_lt_screen '*-t6-sheet'; f="$F"
check_expect "Kethad Wernast" "T6: the dump is the character sheet, so the no-change Enter confirmed"
check_reject "At your next full rest:" "T6: no summary box was drawn for a selection with no change"

# T7 uses a fresh fixture so T5's confirmed forget cannot affect its marks.
check_run tools/keys/learn-table-needs-book.keys "$SEED"
_lt_screen '*-t7-with-book'; f="$F"
grep -F '[*]  Protection from Evil   Arcane' "$f" | grep -qE 'Memorized[[:space:]]*\|$'
_lt_assert $? "T7: with its book, held Arcane Protection from Evil is [*] Memorized"
_lt_screen '*-t7-needs-book'; f="$F"
grep -F '[*]  Protection from Evil   Arcane' "$f" | grep -qE 'Needs book[[:space:]]*\|$'
_lt_assert $? "T7: without its book, held Arcane Protection from Evil is [*] Needs book (untruncated)"
_lt_screen '*-t7-forget'; f="$F"
grep -F 'Protection from Evil   Arcane' "$f" | grep -qE 'Forget at rest[[:space:]]*\|$' \
    && ! grep -F 'Protection from Evil   Arcane' "$f" | grep -qF '[*]'
_lt_assert $? "T7: toggling the missing-book row unmarks it and ends Forget at rest"
for lt_stage in with-book needs-book forget; do
    _lt_screen "*-t7-$lt_stage"; f="$F"
    grep -F '[*]  Protection from Evil   Divine' "$f" | grep -qE 'Memorized[[:space:]]*\|$'
    _lt_assert $? "T7: Divine Protection from Evil stays [*] Memorized ($lt_stage)"
done

check_done "the Learn Spells table pages, wraps, previews its changes in a clear box, applies a confirmed pick, and labels held spells needing a book"
