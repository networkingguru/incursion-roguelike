#!/bin/bash
# gate: live
# Regression check for bd inc-vc44: Aura of Valour's gain line reached the
# player when an ALLY gained the buff.
#
# DEFECT. lib/classes.irh Effect "Aura of Valour" printed "You feel a sacred
# courage come over you." from a bare-string EV_GAIN_STATI handler. A bare
# string goes through APrint to every player who perceives the creature that
# gains the stati, so a tamed monster inside the radius-3 field told the
# player about its own courage. The handler now prints only to EActor.
#
# ORACLE. The message log after the paladin reaches level 2 (his own gain, the
# control: exactly one line), after a tamed kobold stands beside him, and
# after the paladin walks out of the radius and back in. The count of "sacred
# courage" lines MUST stay equal to the control at both later points.
#
# fact: character -- fixture human-paladin-seed4-opt0822
# fact: character level 2 (aura starts) -- wizard Free Advancement + sheet G
# fact: no other creature (Keeper, wild monsters) -- wizard Genocide Everything
# fact: the ally -- wizard Monster Summoning kobold + Make Player Master
# fact: the ally does not wander -- wizard Freeze Monsters
# fact: 5 free squares west of the player -- the fixture's saved map
# fact: no roll decides the line -- none read
#
# Usage: tools/check_valour_ally_message.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: build first with BACKEND=posix ./build_macos.sh"
    exit 2
}

OUT="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
       INCURSION_LOAD=tools/fixtures/chars/human-paladin-seed4-opt0822.sav \
       tools/headless.sh tools/keys/valour-ally-message.keys 1 2>&1)"
STATUS=$?
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCR="$RUN/logs/screens"
echo "screens: $SCR"
if [ "$STATUS" != 0 ]; then
    echo "INCONCLUSIVE: headless session exited $STATUS"
    echo "$OUT" | tail -12
    exit 2
fi

count() {  # $1 = screen label; prints the number of message-box lines, or nothing
    local f
    f=$(ls "$SCR"/*-"$1".txt 2>/dev/null | head -1)
    [ -n "$f" ] || return
    grep -c '^ *| .*sacred courage' "$f"
}

c0=$(count after-level)
c1=$(count after-tame)
c2=$(count after-reentry)
if [ -z "$c0" ] || [ -z "$c1" ] || [ -z "$c2" ]; then
    echo "INCONCLUSIVE: a message-log screen was never taken"
    exit 2
fi
echo "sacred-courage lines: after level-up $c0, after taming $c1, after re-entry $c2"

if [ "$c0" != 1 ]; then
    echo "INCONCLUSIVE: the paladin's own gain reads $c0 lines, expected 1. The key"
    echo "              script has rotted -- nothing was measured."
    exit 2
fi
echo "  ok: the paladin's own gain prints once"

fail=0
if [ "$c1" != "$c0" ]; then
    echo "FAIL: taming a kobold inside the aura added $((c1 - c0)) line(s) for the player."
    fail=1
fi
if [ "$c2" != "$c0" ]; then
    echo "FAIL: the ally's re-entry left $((c2 - c0)) extra line(s) for the player."
    fail=1
fi
if [ "$fail" = 0 ]; then
    echo "PASS: an ally gaining Aura of Valour tells the player nothing"
    exit 0
fi
exit 1
