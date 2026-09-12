#!/bin/bash
# gate: live
# Does a frozen character fixture still load, and is he still the character his
# own sheet claims? (bd inc-1fjk)
#
# WHAT IS BEING GUARDED. A character built by a key script is not reproducible
# across module changes: an rID in this engine is a POSITION, so one resource
# added to lib/ shifts every id above it. Measured 2026-09-12, commit bef32c3
# added one Effect to lib/m_items.irh and the seed-1 Lizardfolk monk went from
# STR 18 holding a long sword +3 to STR 14 holding a quarterstaff, on
# byte-identical attribute dice. A character LOADED from a save does not move,
# because the v1 save schema converts every saved rID through that save's own
# per-module manifest (v1ConvertManifestRid, src/SaveV1.cpp). This check is the
# standing proof of that claim for the first fixture, and the proof that the
# machinery around it -- INCURSION_LOAD in tools/headless.sh,
# tools/make_char_fixture.sh, tools/keys/load-char-sheet.keys -- still works
# end to end.
#
# THE ORACLE IS THE FIXTURE'S OWN SHEET, not a list of numbers typed into this
# file. tools/fixtures/chars/<name>.sheet.txt is written by the same run that
# made the .sav, so a check that reads its expectations out of that file asks
# the only question worth asking: does the save still hold the character its
# audit record says it holds? Numbers copied into a check would drift from the
# fixture the first time somebody regenerated it, and would then be a second
# thing to remember.
#
# TWO STRUCTURAL ASSERTIONS RIDE ALONG, because the screens cannot see them:
# the fixture must be byte-identical after a run that loaded it, and the run's
# sandbox must hold its own copy of it. A loaded session writes back to its own
# save file (Game::SaveGame, src/Registry.cpp:1114) and this check's key script
# makes it save, so without the copy the session would rewrite the fixture --
# and a fixture a run can modify is not frozen.
#
# THE MUTATION, and why it is this one. Every way of breaking the LOAD makes
# the game refuse to start, which tools/headless.sh reports as exit 2 or 5 and
# tools/check_lib.sh reads as INCONCLUSIVE -- and _check_prove_red refuses
# INCONCLUSIVE as evidence, on purpose. The break that leaves a session playing
# is a fixture whose sheet no longer describes its save, so that is what is
# declared: the sheet's STR goes back to 14/00 -> 18/00, which is the exact
# drift bef32c3 caused. It restores the pre-shift claim without touching the
# .sav, the loaded character is unchanged, and the check must notice they
# disagree. The exactly-once guard check_mutation applies on an ordinary run
# is worth having on its own: it fails if the fixture is ever regenerated into
# a character with a different Strength, which is a thing somebody should be
# told about rather than discover.
#
# Usage: tools/check_char_fixture.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The fixture under test. Its settings and seed are recorded in its own sheet;
# they are repeated here because check_run needs them, and a mismatch between
# the two would show up as the character failing to be himself.
FIXTURE=lizardfolk-monk-seed1
SEED=1
SAV="tools/fixtures/chars/$FIXTURE.sav"
SHEET="tools/fixtures/chars/$FIXTURE.sheet.txt"

# Before the mutation, so a missing fixture says how to make one rather than
# reporting that a file the mutation names cannot be found.
for f in "$SAV" "$SHEET"; do
    [ -f "$f" ] || _check_die 2 \
        "no $f, so there is no fixture to check." \
        "Make one with:" \
        "  tools/make_char_fixture.sh $FIXTURE tools/keys/lizardfolk-monk-save.keys $SEED $CHECK_OPTIONS"
done

check_mutation "$SHEET" 'STR: 14/00' 'STR: 18/00'

# ---------------------------------------------------------------------------
# What the fixture claims. Each value is lifted VERBATIM, label and padding
# together, out of the engine's own dump in the sheet: the character sheet the
# session draws on screen comes from the same src/Sheet.cpp fields, so a line
# copied from one is a fixed string that must appear in the other. Building the
# strings here instead would hard-code column widths this check has no business
# knowing.
sheet_line() { # <anchored sed expression> -> the matched text, trailing space cut
    sed -n "$1" "$SHEET" | head -1 | sed 's/[[:space:]]*$//'
}

WANT_RACE="$(sheet_line 's/^\(Race  *[^ ].*\)$/\1/p')"
WANT_CLASS="$(sheet_line 's/^\(Class  *[^ ].*\)$/\1/p')"
WANT_STR="$(sheet_line 's/^\(STR: *[0-9]*\/[0-9]*\).*/\1/p')"
# The engine writes a space inside a name as an underscore in this dump (it is
# the same marker that indents the Spiritual State block), while the screen
# draws the space. Translate rather than assert the underscore, which appears
# on no screen at all.
WANT_NAME="$(sed -n 's/^ *\([^ ,][^,]*\), .*(.*Mode)$/\1/p' "$SHEET" | head -1 | tr '_' ' ')"

for v in "$WANT_NAME" "$WANT_RACE" "$WANT_CLASS" "$WANT_STR"; do
    [ -n "$v" ] || _check_die 2 \
        "$SHEET does not carry the name, race, class and Strength this check" \
        "reads its expectations from, so there is nothing to assert. The sheet" \
        "is written by tools/make_char_fixture.sh; regenerate the fixture."
done

# The same four again with the label cut off, for prose only. The assertions
# above keep the label, because the label is what makes the string unambiguous
# on a screen full of numbers.
say() { printf '%s' "${1#* }" | sed 's/^ *//'; }
SAY_RACE="$(say "$WANT_RACE")"
SAY_CLASS="$(say "$WANT_CLASS")"
SAY_STR="$(say "$WANT_STR")"

echo "  fixture: $FIXTURE claims $WANT_NAME, a $SAY_RACE $SAY_CLASS with STR $SAY_STR"

BEFORE="$(shasum -a 256 "$SAV" | awk '{print $1}')"

# ---------------------------------------------------------------------------
# Load him. The seed still matters even though the character comes from the
# file: it pins everything the session does after the load.
export INCURSION_LOAD="$SAV"
check_run tools/keys/load-char-sheet.keys "$SEED"

check_screens '*-sheet'
check_expect "$WANT_NAME"  "the loaded character is $WANT_NAME"
check_expect "$WANT_RACE"  "he is still a $SAY_RACE"
check_expect "$WANT_CLASS" "he is still a $SAY_CLASS"
check_expect "$WANT_STR"   "his Strength is still the fixture's $SAY_STR"

check_screens '*-saved'
check_expect "Autosave...  Done." "the loaded session saved, so it owned a save file"

# ---------------------------------------------------------------------------
# The two the screens cannot answer.
AFTER="$(shasum -a 256 "$SAV" | awk '{print $1}')"
if [ "$BEFORE" = "$AFTER" ]; then
    echo "  ok    the fixture is byte-identical after a run that loaded AND saved it"
else
    echo "  FAIL  the run changed $SAV"
    echo "        before $BEFORE"
    echo "        after  $AFTER"
    echo "        A loaded session writes back to its own save file, so the"
    echo "        fixture must be copied into the sandbox and never played in"
    echo "        place. INCURSION_LOAD in tools/headless.sh does that copy."
    CHECK_FAIL=1
fi

# The session renames its save on the way past (SaveGame backs the old file up
# before writing), so either name proves the copy was made and used.
if [ -f "$CHECK_RUN/save/$FIXTURE.sav" ] || [ -f "$CHECK_RUN/save/$FIXTURE.sav.backup" ]; then
    echo "  ok    the session played its own copy, in $CHECK_RUN/save"
else
    echo "  FAIL  no copy of $FIXTURE.sav under $CHECK_RUN/save"
    echo "        The session loaded something, but not a copy inside its own"
    echo "        sandbox, so nothing here proves the fixture was protected."
    CHECK_FAIL=1
fi

check_done "$FIXTURE loads as $WANT_NAME, a $SAY_RACE $SAY_CLASS with STR $SAY_STR, and comes through the run byte-identical"
