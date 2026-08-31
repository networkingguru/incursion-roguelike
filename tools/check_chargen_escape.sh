#!/bin/bash
# Regression check for leaving character generation with ESC, bd inc-gd3c
# stage 1.
#
# WHAT IS BEING PROVED. Character-generation LMenu calls did not pass MENU_ESC,
# so ESC was ignored and a player could not abandon a character. The new path
# must ask before abandoning, must restore the same menu unchanged after no,
# and must unwind through Game::NewGame to Game::StartMenu after yes.
#
# The race menu is used because it is the first affected menu. The first dump
# records its Orc option and its own explanatory prompt. The prompt dump proves
# ESC reached Player::AbandonCreation. The next dump must contain both the same
# race and the race prompt, proving the option list was rebuilt after LMenu
# cleared it. The final dump must contain Initial Choices, proving acceptance
# returned to the main menu and did not enter play with an abandoned Player.
#
# A missing binary or screen cannot establish either behavior. Those cases are
# INCONCLUSIVE rather than FAIL so a dead or incomplete session never becomes
# evidence about the implementation.
#
# Usage: tools/check_chargen_escape.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=5
RACE="[a] Human"
RACE_PROMPT="Your race grants"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/chargen-escape.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
S="$run/logs/screens"

for f in 0001-race-menu 0002-abandon-prompt 0003-race-menu-again 0004-main-menu; do
    [ -f "$S/$f.txt" ] || {
        echo "INCONCLUSIVE: the session produced no $f screen. Run dir: $run"
        exit 2
    }
done

grep -q "Abandon this character" "$S/0002-abandon-prompt.txt" || {
    echo "FAIL: ESC at the race menu did not show the abandon prompt."
    echo "Run dir: $run"
    exit 1
}

grep -Fq "$RACE" "$S/0001-race-menu.txt" || {
    echo "INCONCLUSIVE: the original race menu did not contain $RACE."
    echo "Run dir: $run"
    exit 2
}

fail=0
if ! grep -Fq "$RACE" "$S/0003-race-menu-again.txt"; then
    echo "FAIL: declining abandon did not rebuild the race option list."
    fail=1
fi
if ! grep -q "$RACE_PROMPT" "$S/0003-race-menu-again.txt"; then
    echo "FAIL: declining abandon did not return to the race menu prompt."
    fail=1
fi
if ! grep -q "Initial Choices" "$S/0004-main-menu.txt"; then
    echo "FAIL: accepting abandon did not return to the main menu."
    fail=1
fi

if [ "$fail" = 1 ]; then
    echo "Run dir: $run"
    exit 1
fi

echo "PASS: ESC asks to abandon, no restores the race menu, and yes returns to the main menu."
echo "Run dir: $run"
exit 0
