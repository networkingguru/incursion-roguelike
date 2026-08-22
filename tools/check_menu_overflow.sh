#!/bin/bash
# Regression check for the menu that ran out of letters, inc-ysa.
#
# WHAT THE DEFECT WAS. TextTerm::LMenu names each option with a letter taken
# from MenuLetters -- "abc...xyzABC...XYZ" followed by two spaces of padding
# (src/TextTerm.cpp). The draw wrote MenuLetters[min(53,i)] and the keypress
# resolved back through strchr() into the same string, so an option past the
# 52nd got a space: it was drawn "[ ]" and no key could name it. A space does
# not reach the lookup either -- `case ' '` eats it first -- so the padding was
# never a key. The roguelike keyset has only 36 letters and lost everything
# past the 36th the same way.
#
# WHO IT HIT. Any menu with more than 52 options. The one every player meets is
# the first-level feat menu of a full spellcaster: metamagic pushes the list
# past the alphabet. A Wood Elf Druid at seed 7 is offered 88 feats, of which 36
# -- Natural Aptitude, Skill Focus, Quicken Spell, Woodsman and the
# "(Show All Feats)" escape hatch among them -- could not be chosen at all.
#
# THE FIX, and what this check is really watching. Menus that fit the alphabet
# are untouched. A menu that does not now pages: it draws no more rows than it
# has letters for, TAB turns the page, and every drawn row carries the letter
# that selects it. So the assertion is not "the letters got longer" but "the
# entry can be reached by a key", which is what the player lost.
#
# HOW THE RUN PROVES IT. tools/keys/menu-overflow.keys builds the druid and
# uses @choose, which reads the letter the game printed beside the name and
# presses it. On a build with the defect there is no letter to read, so @choose
# refuses and tools/headless.sh ends with exit 6 -- it cannot press the wrong
# key and pass. The run then finishes the character and scrolls his sheet to
# the Feats block, so the pass needs the feat to have been taken and kept, not
# merely a menu that looked right.
#
# Measured 2026-08-22, seed 7, src/TextTerm.cpp the only file different between
# the two builds:
#
#   before: incursion: @choose (that entry has no letter; use @cursorto and
#           ENTER) "Natural Aptitude" failed
#   after:  the character sheet reads "Natural Aptitude" in its Feats block
#
# Usage: tools/check_menu_overflow.sh [seed]
# Ends:  0 pass, 1 fail, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${1:-7}"
KEYS="tools/keys/menu-overflow.keys"
BIN="${INCURSION_BIN:-./incursion-headless}"
WANT="Natural Aptitude"

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: no key script at $KEYS"; exit 2; }

OUT="$(INCURSION_BIN="$BIN" tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCREENS="$RUN/logs/screens"

# The failure the defect produces, named exactly. Anything else that stops the
# run is a broken key script or a broken game, not this bug, and must not be
# reported as this bug.
if echo "$OUT" | grep -q "that entry has no letter"; then
    echo "FAIL: the feat menu drew '[ ]' beside an option and no key selects it."
    echo "      A menu longer than MenuLetters is losing its overflow again."
    echo "      See LMenu in src/TextTerm.cpp: the draw must letter each row"
    echo "      from its position on the page, and the keypress must add"
    echo "      vStart back. inc-ysa."
    echo "      Screens: $SCREENS"
    exit 1
fi

if echo "$OUT" | grep -qE "^ended:.*(never showed|key budget|watchdog)"; then
    echo "INCONCLUSIVE: the session did not finish, so it says nothing about"
    echo "              menu overflow. The chargen questions have probably"
    echo "              moved; fix $KEYS first."
    echo "$OUT" | sed -n '/--- after the session ---/,$p'
    exit 2
fi

if [ ! -d "$SCREENS" ]; then
    echo "INCONCLUSIVE: no screen dumps at $SCREENS"
    exit 2
fi

# The control. A run whose druid never reached the dungeon measured nothing,
# and calling that a pass is the mistake of inc-loa.3.
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: the run never entered a map, so it measured nothing."
    echo "              Screens: $SCREENS"
    exit 2
fi

# The assertion that bites: the feat is on the finished character.
if grep -qh "$WANT" "$SCREENS"/*.txt; then
    echo "PASS: a Wood Elf Druid took Natural Aptitude -- the 61st of 88 feats"
    echo "      offered -- by pressing the letter beside its name, and carries"
    echo "      it on his character sheet."
    exit 0
fi

echo "FAIL: the run finished but no screen shows '$WANT'."
echo "      The menu handed back some other option, or the feat did not stick."
echo "      Screens: $SCREENS"
exit 1
