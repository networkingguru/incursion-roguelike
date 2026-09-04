#!/bin/bash
# Regression check for inc-2sv: target prompts refused any square holding a
# staircase, because rmtew's #187 Enter guard sat in the shared target prompt
# (src/Term.cpp) and ran on every ENTER in every prompt. Portal::EnterDir
# (CENTER) is false for up and down stairs, and a character stands on the stair
# the moment he enters a level, so no potion, wand, spell or fired missile
# could confirm a target on a staircase. The fix deletes the shared block and
# re-sites the guard at its one real site, Player::YuseMenu.
#
# This runs on a character generated FROM SCRATCH -- no save fixture. A
# standard orc barbarian (tools/keys/target-enter-stair.keys, seed 1) is placed
# on the cave-entrance up staircase the moment he enters level 1, and starts
# with Potions of Cure Disease, so the session reproduces Brian's original
# report exactly. See that key script for the scene in full.
#
# THREE ASSERTIONS, all from one session. The scene and the guard are checked
# before the quaff, because an unfixed build's quaff prompt never closes and
# swallows every later keystroke:
#
#   1. THE SCENE IS REAL. He steps one square east and the vacated spawn square
#      renders '<' immediately west of '@'. Without this a seed that spawned
#      him off a stair could pass assertion 3 on an unfixed build, because a
#      non-stair square was never refused. Absent -> INCONCLUSIVE.
#
#   2. THE #187 GUARD SURVIVES. Standing on Floor, he opens the 'y' menu,
#      chooses [u] Enter, confirms the default self-target, and must be refused
#      with "You can't go in anything here" from the guard's new home in
#      Player::YuseMenu. Removing the guard hands a non-portal to the script
#      engine -- the #187 choke -- and drops this message.
#
#   3. THE BUG IS FIXED. He steps back onto the staircase and quaffs a Potion
#      of Cure Disease (Q_TAR|Q_NEAR), confirming the self-target on the stair
#      with ENTER. The quaff must complete: the game returns to play mode
#      (screen "mode 2") and a turn passes. Before the fix the ENTER was read
#      as "walk into the stair", silently declined, and the prompt stayed open
#      (screen "mode 9") with no turn spent -- which is red here.
#
# Usage: tools/check_target_enter.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

OUT="$(tools/headless.sh tools/keys/target-enter-stair.keys 1 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCREENS="$RUN/logs/screens"

STEPPED="$SCREENS/0002-stepped.txt"
AFTERE="$SCREENS/0004-after-enter.txt"
BACK="$SCREENS/0005-back-on-stair.txt"
PROMPT="$SCREENS/0006-target-prompt.txt"
AFTERQ="$SCREENS/0007-after-quaff.txt"

for f in "$STEPPED" "$AFTERE" "$BACK" "$PROMPT" "$AFTERQ"; do
    [ -f "$f" ] || {
        echo "INCONCLUSIVE: the session did not reach $(basename "$f"). Run: $RUN"
        exit 2
    }
done

# The "turn NNNN" stamp lives in every dump's header line.
turn_of() { sed -n '1s/.*turn \([0-9]*\).*/\1/p' "$1"; }

# --- assertion 1 first: is the scene the one we think it is? ----------------
# The vacated spawn square must show '<' immediately west of '@' on the map.
grep -q "<@" "$STEPPED" || {
    echo "INCONCLUSIVE: after stepping east the character is not standing beside"
    echo "              the '<' he spawned on, so this seed does not put him on"
    echo "              a staircase and the quaff below proves nothing. Run: $RUN"
    exit 2
}

# The quaff must actually have opened a target prompt, or the potion letter
# drifted and nothing was aimed at the stair.
grep -q "Choose your target" "$PROMPT" || {
    echo "INCONCLUSIVE: quaffing the potion did not open a target prompt. The"
    echo "              drink-menu letters may have moved. Screen: $PROMPT"
    exit 2
}

fail=0

# --- assertion 2: the re-sited #187 guard still refuses a non-portal --------
if grep -q "You can't go in anything here" "$AFTERE"; then
    echo "  ok: the Enter verb still refuses a non-portal square (#187 guard)"
else
    echo "FAIL: the Enter verb did not refuse a non-portal square. The #187"
    echo "      guard is gone from Player::YuseMenu, so a non-portal now reaches"
    echo "      the script engine (the #187 choke). Screen: $AFTERE"
    fail=1
fi

# --- assertion 3: the bug is fixed -- the self-target on the stair took ------
# The baseline is the turn just before the quaff (back on the stair), so the
# delta is the quaff's alone -- the steps before it spend turns of their own.
T_BEFORE="$(turn_of "$BACK")"
T_AFTER="$(turn_of "$AFTERQ")"
if grep -q "mode 2" "$AFTERQ" && [ -n "$T_BEFORE" ] && [ -n "$T_AFTER" ] \
   && [ "$T_AFTER" -gt "$T_BEFORE" ]; then
    echo "  ok: quaffed a targeted potion on the staircase (+$((T_AFTER - T_BEFORE)) turns)"
else
    echo "FAIL: confirming a target on the staircase square did not take. The"
    echo "      quaff never completed -- the prompt is still open and no turn"
    echo "      was spent. This is inc-2sv: the shared ENTER/portal guard is"
    echo "      refusing the stair. before=$T_BEFORE after=$T_AFTER"
    echo "      Screen: $AFTERQ"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: a target prompt accepts a staircase square, and the #187 guard"
    echo "      still refuses a non-portal Enter (inc-2sv)"
    exit 0
fi
exit 1
