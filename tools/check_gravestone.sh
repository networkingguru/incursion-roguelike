#!/bin/bash
# Regression check for the death screen's epitaph (bd inc-r6z).
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
# Getting there. tools/keys/gravestone.keys replays the one reproducible
# confirmed death this repository already keeps -- tools/keys/dive.keys at seed
# 11 under the pinned gate settings, the scenario tools/check_headless.sh:387
# uses -- and then answers the "You die... Die? [yn]" prompt and presses ENTER
# until Player::Gravestone() has drawn. The settings must be pinned: the live
# Options.Dat is whatever Brian last played with, and OPT_NODEATH is what turns
# the killing blow into that prompt.
#
# Proved RED before it was believed: run against a binary built with the word
# spelt REQUISCANT, this fails on the assertion below.
#
# Usage: tools/check_gravestone.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=11
KEYS=tools/keys/gravestone.keys
OPTS="$ROOT/tools/gates/Options.Dat"

# The epitaph line exactly as the screen must show it. The leading spaces are
# part of the assertion: they are what proves the fix did not shift the
# drawing, and REQUISCANT and REQUIESCAT are both ten characters so it should
# not have.
WANT='      |       REQUIESCAT IN PACE,       |'

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}
[ -f "$OPTS" ] || {
    echo "FAIL: the pinned gate settings are missing: $OPTS"
    exit 1
}

OUT="$(INCURSION_OPTIONS="$OPTS" tools/headless.sh "$KEYS" "$SEED" 2>&1 < /dev/null)"
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

SCREEN="$RUN/logs/screens/0011-gravestone.txt"
if [ ! -f "$SCREEN" ]; then
    SCREEN="$(ls "$RUN"/logs/screens/*-gravestone.txt 2>/dev/null | tail -1)"
fi
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

echo "  ok: $(grep -m1 'IN PACE' "$SCREEN")"
echo "PASS: the death screen reads REQUIESCAT IN PACE, in its original columns"
echo "      ($SCREEN)"
exit 0
