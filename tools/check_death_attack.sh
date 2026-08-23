#!/bin/bash
# Regression check for the Assassin's Death Attack gate, bd inc-tek.24,
# finding PA-03-F28 of bd inc-tek.8.3.
#
# THE DEFECT. The class page attaches the out-of-combat condition to the
# assassin alone (lib/prestige.irh:520-524). The gate demanded it of the target
# as well:  if (EActor->isFlatFooted() && EVictim->isFlatFooted()).
# isFlatFooted() is not the D&D flat-footed condition; it is a per-creature
# out-of-combat counter, FFCount > min(5,10+Mod(A_WIS)) (inc/Creature.h:567-568),
# and any strike zeroes it for both fighters (src/Fight.cpp:3150-3151). So a
# target that was already fighting could never be assassinated, not even unseen
# and from behind while the party held it. The EVictim term is now gone.
#
# THE ORACLE is the ability's own message. Death Attack announces itself either
# way -- "You assassinate the <victim>!" when the Fortitude save fails, "The
# <victim> resists your death attack!" when it holds -- so the check does not
# depend on a saving throw. Neither line can appear unless the gate opened.
#
# TWO STRIKES, and the control is not optional. tools/keys/assassin-engaged-target.keys
# summons one victim of each kind and strikes both:
#
#   goblin    no Improved Initiative -> Monster::Initialize leaves FFCount 20
#             -> relaxed -> assassinated BEFORE the fix and after it. This is
#             what stops a "fix" that merely broke the ability from passing.
#   grippli   Improved Initiative    -> Monster::Initialize sets FFCount 0
#             -> not relaxed -> assassinated ONLY after the fix.
#             (src/Monster.cpp:1443-1446, lib/mon2.irh:3865)
#
# EVERY STRIKE MUST ALSO SAY "Catching him unaware". That line is the engine's
# own report that the blow landed unperceived (src/Fight.cpp:3155-3157), and it
# separates the two failures that otherwise look identical: a victim that
# spotted the assassin, and a gate that refused a victim he approached
# perfectly. Without it a missed Hide roll would read as a broken fix.
#
# PROVED RED FIRST. With the EVictim term put back and the module rebuilt, the
# goblin was still assassinated and the grippli was not -- its line read "you
# deliver a killing blow, killing the grippli" with no death attack in it.
#
# Usage: tools/check_death_attack.sh     (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/assassin-engaged-target.keys
SEED=1

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCREENS="$RUN/logs/screens"

if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi

# The message area wraps mid-word against the sidebar, so every comparison is
# made on the text with all whitespace removed. That is wrap-proof; matching
# whole words is not.
messages() {    # messages <dump label> -> the message area, lowercased, unspaced
    local f="$SCREENS/$1"
    [ -f "$f" ] || { echo ""; return; }
    sed -n '2,5p' "$f" | cut -c1-64 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'
}

GOBLIN="$(messages 0003-0003-goblin-struck.txt)"
GRIPPLI="$(messages 0007-0007-grippli-struck.txt)"

if [ -z "$GOBLIN" ] || [ -z "$GRIPPLI" ]; then
    echo "FAIL: one of the two strikes left no screen dump in $SCREENS"
    echo "      run: $RUN"
    exit 1
fi

unaware() { case "$1" in *catchinghimunaware*) return 0;; *) return 1;; esac; }
deathattack() {
    case "$1" in
        *youassassinatethe*)      return 0;; # the save failed
        *resistsyourdeathattack*) return 0;; # the save held; the gate still opened
        *)                        return 1;;
    esac
}

if ! unaware "$GOBLIN"; then
    echo "FAIL: the goblin was not struck unperceived, so nothing was measured."
    echo "      The assassin's Hide roll, not the gate, decided this run."
    echo "      dump: $SCREENS/0003-0003-goblin-struck.txt"
    exit 1
fi

if ! deathattack "$GOBLIN"; then
    echo "FAIL: the CONTROL failed. A relaxed victim, struck unperceived by an"
    echo "      assassin who was himself out of combat, was not death-attacked."
    echo "      Death Attack is broken outright, not merely gated."
    echo "      dump: $SCREENS/0003-0003-goblin-struck.txt"
    exit 1
fi

if ! unaware "$GRIPPLI"; then
    echo "FAIL: the grippli was not struck unperceived, so nothing was measured."
    echo "      dump: $SCREENS/0007-0007-grippli-struck.txt"
    exit 1
fi

if ! deathattack "$GRIPPLI"; then
    echo "FAIL: a victim that was NOT relaxed could not be death-attacked, which"
    echo "      is the defect itself. The gate is reading the victim's"
    echo "      out-of-combat counter again -- see lib/prestige.irh, the"
    echo "      META(PRE(EV_STRIKE)) handler of Effect \"Death Attack\"."
    echo "      dump: $SCREENS/0007-0007-grippli-struck.txt"
    exit 1
fi

echo "PASS: both victims were death-attacked, and both blows landed unperceived."
echo "      goblin  (FFCount 20, relaxed)     -- the control"
echo "      grippli (FFCount 0, not relaxed)  -- the case the old gate refused"
echo "      run: $RUN"
exit 0
