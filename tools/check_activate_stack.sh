#!/bin/bash
# Regression check for the item that vanished out of a stack when one of it was
# activated, bd inc-od6j.
#
# WHAT IS BEING PROVED. Item::Activate (src/Magic.cpp) begins by calling
# Item::TakeOne() when the stack holds more than one unit. TakeOne() ALWAYS
# leaves its unit outside the actor's pack -- it either Remove(false)s the last
# one of a stack or hands back a fresh, parentless copy -- so every path out of
# Activate owes that unit a disposal. Activate had none on any path, success
# included. Unlike a potion or a scroll, a rod, a horn or a circlet is not
# spent by being used, so EVERY activation of one of a stack destroyed one unit
# of it. The give-back existed in the original source and an upstream author
# commented it out because it interfered with the Rod of the Python, an item
# that transforms itself; the F_DELETE guard inside the commented block is
# exactly what made that disable unnecessary.
#
# THE ORACLE IS THE GAME'S OWN ACTIVATE MENU. Player::ItemMenu writes a stack
# held in a container as "(in pack) 3 Horns of Plenty", so the count is printed
# by the game, on screen, in words, both before and after. Measured on seed 4,
# tools/keys/activate-stack.keys, src/Magic.cpp the only file different between
# the two builds:
#
#   blow one of three Horns of Plenty   before: 3 Horns of Plenty -> 2
#                                       after:  3 Horns of Plenty -> 3
#
# THE SECOND HALF IS NOT DECORATION. A "fix" that keeps the stack whole by
# never firing the effect would pass the count test and break every activated
# item in the game. So the check also demands the Plenty effect's own sentence,
# "Fruits and produce appear at your feet!" (lib/m_items.irh), on the screen
# dumped immediately after the activation. Both halves must hold.
#
# A RUN THAT MEASURED NOTHING IS INCONCLUSIVE, NOT A PASS AND NOT A FAILURE.
# The wizard-mode acquisition list has no menu letters, so the key script walks
# a glyph strip by a counted number of RIGHT presses; a new glyph category
# ahead of Horns would acquire something else entirely. If the activate menu
# does not show three Horns of Plenty before anything is blown, the session
# says nothing about this bug. Sending somebody hunting a regression that a
# dead session invented is the mistake of inc-loa.3.
#
# Usage: tools/check_activate_stack.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=4
STACK="3 Horns of Plenty"
FIRED="Fruits and produce appear at your feet!"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# The pinned options file, not the live one: the live Options.Dat is whatever
# the owner last played with and the game rewrites it every session, which has
# already moved a screen out from under a comparison once (tools/README.md,
# trap 2).
out="$(INCURSION_OPTIONS=tools/gates/Options.Dat \
       tools/headless.sh tools/keys/activate-stack.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
S="$run/logs/screens"

if echo "$out" | grep -qE 'NO GAMEPLAY|the key script looked for something'; then
    echo "INCONCLUSIVE: the session did not complete its measurement."
    echo "$out"
    exit 2
fi

for f in 0001-menu-before 0002-blown 0003-menu-after; do
    [ -f "$S/$f.txt" ] || {
        echo "INCONCLUSIVE: the session produced no $f screen. Run dir: $run"
        exit 2
    }
done

# Did wizard mode actually hand over three stacked horns? Without this the
# check cannot tell a preserved stack from a stack that was never there.
grep -q "$STACK" "$S/0001-menu-before.txt" || {
    echo "INCONCLUSIVE: the activate menu does not offer \"$STACK\" before the"
    echo "              test, so nothing was measured. Either the RIGHT count"
    echo "              into the acquisition glyph strip has drifted, or the"
    echo "              three horns did not stack. Run dir: $run"
    exit 2
}

fail=0

# 1. Activating one of a stack must cost the stack nothing.
if ! grep -q "$STACK" "$S/0003-menu-after.txt"; then
    echo "FAIL: after blowing one horn the activate menu no longer offers"
    echo "      \"$STACK\" -- activating one of a stack destroyed a unit."
    grep -m1 -o "[0-9]* Horns* of Plenty" "$S/0003-menu-after.txt" |
        sed 's/^/      now: /'
    fail=1
fi

# 2. The activation must still have done something.
if ! grep -qF "$FIRED" "$S/0002-blown.txt"; then
    echo "FAIL: the horn was activated and the game never printed"
    echo "      \"$FIRED\" -- the stack may only be intact because the effect"
    echo "      never fired."
    fail=1
fi

if [ "$fail" = 1 ]; then
    echo "Run dir: $run"
    exit 1
fi

echo "PASS: blowing one of three Horns of Plenty keeps all three and still"
echo "      conjures the food."
echo "Run dir: $run"
exit 0
