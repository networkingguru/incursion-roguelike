#!/bin/bash
# Does activating a blast item from the y menu ask where to aim it? bd inc-azc.
#
# THE DEFECT. Brian pressed y, chose Activate, chose a Circlet of Blasting, was
# never asked for a direction or a target, and the beam hit him. The item
# script is not at fault: lib/m_items.irh:5440 declares qval: Q_DIR|Q_TAR on
# the head of the effect chain, and every other activated blast item in lib/
# declares one too. Player::YuseMenu (src/Player.cpp) simply never read it.
# The Activate row of YuseCommands (src/Tables.cpp:3052) carries QTarget 0 --
# it must, because the query belongs to whichever item the player picks -- and
# nothing after the item menu asked the item. With no target chosen,
# Magic::MagicEvent (src/Magic.cpp:734) makes the activator the victim.
#
# THE ORACLE is the message line. A run that was asked to aim shows the prompt
# TextTerm::EffectPrompt writes for Q_DIR|Q_TAR, "Select direction or target".
# A run that was not shows the beam resolving on the spot, on the only
# creature in range, which is the player: "Your own beam strikes you!". The two
# are mutually exclusive and both are the game's own words, not the check's.
#
# WHY THE 'a' COMMAND IS MEASURED TOO. Player::ItemMenu (src/Player.cpp:1435)
# has always asked the item for its qval, so the same circlet on the same turn
# prompts under 'a' and did not under 'y'. That second half is what stops this
# from being "fixed" by deleting the query: it pins the behaviour the y route
# was supposed to have to a route that already had it, using one item, one
# character and one seed. Before the fix the 'y' half was red and the 'a' half
# was green.
#
# Usage: tools/check_yuse_activate.sh     (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
fail=0

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# One scripted session per command under test. Both make the same character
# with the same seed and give him the same circlet; they differ in the last
# three keystrokes.
run_case() { # <keyscript> -> echoes the run directory
    local out run
    out="$(tools/headless.sh "$1" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q "the key script looked for something"; then
        echo "INCONCLUSIVE: $1 could not find something on screen. Run: $run" >&2
        exit 2
    fi
    echo "$run"
}

# The wizard-mode acquisition list has no menu letters, so the key script walks
# a cursor to a row it counted. Read the item's name back before trusting any
# of it: a list that gained an entry would silently activate the neighbour.
assert_right_item() { # <run dir>
    local menu="$1/logs/screens/0001-activate-menu.txt"
    [ -f "$menu" ] || {
        echo "INCONCLUSIVE: no activate menu was dumped in $1" >&2
        exit 2
    }
    grep -q "Circlet of Blasting" "$menu" || {
        echo "INCONCLUSIVE: the character never got a Circlet of Blasting, so" >&2
        echo "              the session measured nothing. Screen: $menu" >&2
        exit 2
    }
}

# --- the y menu, which is the command the bug was reported against -----------
YRUN="$(run_case tools/keys/yuse-activate-blast.keys)"
assert_right_item "$YRUN"
YSCREEN="$YRUN/logs/screens/0002-after-activate.txt"

if grep -q "Select direction or target" "$YSCREEN"; then
    echo "  ok: y -> Activate asked where to aim the circlet"
elif grep -q "Your own beam strikes you" "$YSCREEN"; then
    echo "FAIL: y -> Activate fired the circlet at the activator with no prompt"
    echo "      $(grep -m1 -h "Your own beam" "$YSCREEN" | tr -s ' ')"
    echo "      screen: $YSCREEN"
    fail=1
else
    echo "INCONCLUSIVE: the y run neither prompted nor blasted. Screen: $YSCREEN"
    exit 2
fi

# --- the a command, which is the same query on a route that always had it ----
ARUN="$(run_case tools/keys/a-activate-blast.keys)"
assert_right_item "$ARUN"
ASCREEN="$ARUN/logs/screens/0002-after-activate.txt"

if grep -q "Select direction or target" "$ASCREEN"; then
    echo "  ok: a asked where to aim the same circlet"
else
    echo "FAIL: a did not prompt either, so the two routes agree for the wrong"
    echo "      reason. screen: $ASCREEN"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: both routes to an activated blast ask for a target"
    exit 0
fi
exit 1
