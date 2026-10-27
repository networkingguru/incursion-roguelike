#!/bin/bash
# Regression check for the death screen (bd inc-r6z, bd inc-pg5).
#
# Two assertions, both on one rendered gravestone: the epitaph's wording and
# columns (inc-r6z), and the date the stone is carved with (inc-pg5).
#
# The gravestone read "REQUISCANT IN PACE," (src/Main.cpp, GravestoneImage) and
# there is no such Latin word. The phrase R.I.P. abbreviates is "requiescat in
# pace"; the plural is "requiescant". Both keep the 'e' the drawing dropped.
# Singular is right here, because the stone names one character.
#
# The oracle is the screen a dying player sees, not the source. Player::
# Gravestone() draws GravestoneImage through XPrint, which eats the <8>/<7>
# colour codes, and then writes the character's name, class, killer and date
# into fixed columns of the same picture. So a change to the drawing can move
# every one of those, and only a rendered screen shows whether it did. This
# check therefore reads a real screen dump and asserts on the whole epitaph
# LINE, indentation included -- not just on the word.
#
# Getting there. src/GravestoneProbe.cpp, switched on by INCURSION_GRAVESTONE_PROBE,
# deals 30000 AD_NORM damage to the loaded character after his first completed
# turn, through ThrowDmg(EV_DAMAGE) -- the path a monster's blow takes -- with
# the fixed killer text "gravestone probe". No roll is involved. The pinned gate
# settings run with OPT_NODEATH on, so the killing blow asks "You die... Die?
# [yn]" and tools/keys/gravestone.keys answers it, presses ENTER until
# Player::Gravestone() has drawn, and dumps the screen. The settings must be
# pinned: OPT_NODEATH is what turns the killing blow into that prompt. The
# harness reports the death as confirmed twice (the probe's damage ends in
# Creature::CalcValues' "Belatedly, you drop dead", which throws EV_DEATH again);
# the check requires at least one.
#
# Seed-independent (inc-nx0z; this check used to replay dive.keys at seed 11 and
# fail the day that walk stopped killing him). Facts the check reads:
# fact: character (name, class, turn of death) -- fixture orc-barbarian-seed1-gate (INCURSION_LOAD)
# fact: settings, OPT_NODEATH on -- INCURSION_OPTIONS=tools/gates/Options.Dat
# fact: the killing blow and its roll -- GravestoneProbe, 30000 damage, no roll
# fact: killer text on the stone -- the probe's fixed string "gravestone probe"
# fact: the day carved on the stone -- derived from the dump header's turn
# fact: the Die? prompt and the screen's timing -- keys y*3, ENTER, @dump
#
# Proved RED before it was believed: run against a binary built with the word
# spelt REQUISCANT, this fails on the assertion below.
#
# Usage: tools/check_gravestone.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/gravestone.keys
OPTS="$ROOT/tools/gates/Options.Dat"
LOAD="$ROOT/tools/fixtures/chars/orc-barbarian-seed1-gate.sav"

# The epitaph line exactly as the screen must show it. The leading spaces are
# part of the assertion: they are what proves the fix did not shift the
# drawing, and REQUISCANT and REQUIESCAT are both ten characters so it should
# not have.
WANT='      |       REQUIESCAT IN PACE,       |'

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}
[ -f "$LOAD" ] || {
    echo "FAIL: the character fixture is missing: $LOAD"
    exit 1
}
[ -f "$OPTS" ] || {
    echo "FAIL: the pinned gate settings are missing: $OPTS"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-gravestone"
OUT="$(INCURSION_GRAVESTONE_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" INCURSION_OPTIONS="$OPTS" \
    INCURSION_LOAD="$LOAD" tools/headless.sh "$KEYS" "$SEED" 2>&1 < /dev/null)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"

# A session that measured nothing must never read as a pass -- that mistake is
# inc-loa.3.
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi

# ... and neither must a session that never died. Without this the assertion
# below would fail for the wrong reason the day the seed stops killing him,
# and somebody would go looking at the drawing instead of at the key script.
if ! echo "$OUT" | grep -q '^death:.*confirmed'; then
    echo "FAIL: the character never died, so no gravestone was ever drawn."
    echo "$OUT" | grep -E '^(ended|death|stuck-prompt):'
    exit 1
fi

SCREEN="$(ls "$RUN"/logs/screens/*-gravestone.txt 2>/dev/null | tail -1)"
if [ -z "$SCREEN" ] || [ ! -f "$SCREEN" ]; then
    echo "FAIL: the session dumped no gravestone screen under $RUN/logs/screens"
    exit 1
fi

# Third guard: the dump has to BE the gravestone. A screen taken one keystroke
# early is still a file, is still 48 lines long, and would fail the assertion
# without telling anybody why.
if ! grep -q "WAS KILLED BY" "$SCREEN"; then
    echo "FAIL: $SCREEN is not the gravestone screen"
    exit 1
fi

# The killer is the probe's fixed text, so it is asserted whole.
if ! grep -qxF '      |        gravestone probe         |' "$SCREEN"; then
    echo "FAIL: the stone does not name the killer 'gravestone probe'"
    grep -n -A2 "WAS KILLED BY" "$SCREEN"
    exit 1
fi

if grep -q "REQUISCANT" "$SCREEN"; then
    echo "FAIL: the epitaph still reads REQUISCANT, which is not a Latin word"
    grep -n "IN PACE" "$SCREEN"
    exit 1
fi

if ! grep -qxF "$WANT" "$SCREEN"; then
    echo "FAIL: the epitaph line is not what it should be."
    echo "  wanted: [$WANT]"
    echo "  got:    [$(grep -m1 'IN PACE' "$SCREEN")]"
    echo "  screen: $SCREEN"
    exit 1
fi

# ---------------------------------------------------------------------------
# The date the stone carries (bd inc-pg5).
#
# The line under "ON THE" was sprintf(buff,"12th of Suntide") -- a constant, so
# every dead character was buried on the same day. It now comes from GameDate()
# (src/Term.cpp), which turns theGame->GetTurn() into a date.
#
# This assertion is DERIVED, not recorded: the screen dump's own header names
# the turn the dump was taken on, and the calendar below re-implements the
# arithmetic independently of the code under test. So it does not pass merely
# because tonight's run printed what tonight's run printed, and it does not
# accept "12th of Suntide" unless the character really did die on that day.
# The calendar is the game's, not this script's: 432000 turns to a day, thirty
# days to a month, twelve months to a year, and the ordinal suffixes of
# NumPrefix() (inc/Inline.h).
#
# It asserts the whole LINE, indentation included, for the same reason the
# epitaph assertion does: the date is centred on column 23 by
# 23-length/2, and a date of a different width than the old constant must still
# come out centred there.
#
# Proved RED before it was believed: run against a binary still carrying
# sprintf(buff,"12th of Suntide"), this fails with
#   wanted: [      |         1st of Suntide          |]
#   got:    [      |         12th of Suntide         |]

TURN="$(sed -n '1s/.*turn \([0-9][0-9]*\).*/\1/p' "$SCREEN")"
if [ -z "$TURN" ]; then
    echo "FAIL: $SCREEN has no turn in its header, so the date cannot be derived"
    head -1 "$SCREEN"
    exit 1
fi

MONTHS=(Suntide Harvest Leafdry Softwind Thincold Deepcold Midwint Arvester \
        Reprise Icemelt Turnleaf Blossom)
DAY=$(( TURN / 432000 ))
DOM=$(( DAY % 30 + 1 ))
MONTH="${MONTHS[$(( (DAY / 30) % 12 ))]}"
case $DOM in
    1[0-9]) SUF=th ;;
    *1)     SUF=st ;;
    *2)     SUF=nd ;;
    *3)     SUF=rd ;;
    *)      SUF=th ;;
esac
DATE="$DOM$SUF of $MONTH"

# Centre it the way Player::Gravestone() must: text starts at column
# 23-length/2, the stone's left wall is at column 6 and its right wall at
# column 40.
LEN=${#DATE}
START=$(( 23 - LEN / 2 ))
if [ "$START" -lt 7 ]; then
    echo "FAIL: the derived date [$DATE] is too wide for the stone"
    exit 1
fi
PAD1=$(( START - 7 ))
PAD2=$(( 40 - START - LEN ))
WANTDATE="$(printf '      |%*s%s%*s|' "$PAD1" "" "$DATE" "$PAD2" "")"

if ! grep -qxF "$WANTDATE" "$SCREEN"; then
    echo "FAIL: the death date is not what turn $TURN implies."
    echo "  wanted: [$WANTDATE]"
    echo "  got:    [$(grep -m1 ' of ' "$SCREEN")]"
    echo "  screen: $SCREEN"
    exit 1
fi

echo "  ok: $(grep -m1 'IN PACE' "$SCREEN")"
echo "  ok: $(grep -m1 -xF "$WANTDATE" "$SCREEN")   (turn $TURN -> day $DAY)"
echo "PASS: the death screen reads REQUIESCAT IN PACE, in its original columns"
echo "      and is dated $DATE, which is the day turn $TURN falls on"
echo "      ($SCREEN)"
exit 0
