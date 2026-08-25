#!/bin/bash
# Regression check for inc-wcf: the false unsafe-terrain warning on descent.
#
# WHAT WAS WRONG. Portal::Enter (src/Feature.cpp) asked "The stair leads to
# <terrain>. Confirm unsafe action?" before every descent. Two faults in one
# prompt. The test that decided whether the arrival square was unsafe was
# commented out above the prompt, so the prompt was unconditional. And the
# square it named was the player's own coordinates read off the NEW map, which
# Player::MoveDepth throws away when it is solid or part of a vault: it re-rolls
# a random open square instead. So "the stair leads to Dungeon Wall" was false
# by construction. Brian met it on 2026-08-21 on an ordinary staircase.
#
# WHAT THIS ASSERTS, from one restored session that climbs down one staircase:
#
#   A. the character loaded, stood on depth 2, and pressed '>'
#   B. no screen shows the confirmation prompt. On THIS staircase a prompt is
#      always wrong: the square the player would keep is solid, so MoveDepth
#      refuses it and re-rolls an open one, and a re-rolled square is never
#      the wall the message names
#   C. every descent the probe recorded obeys the rule -- the player is asked
#      if and only if the arrival square survives MoveDepth's placement rules
#      AND the terrain's own EV_MON_CONSIDER calls that square unsafe
#   D. the descent happened: the status line reads 030m afterwards, not 020m.
#      Before the fix it read 020m, because the run sat at the [yn] prompt
#      with no key left to answer it
#
# B is red on the build before the fix, with the prompt on the screen dump.
#
# ponytail: C is only as strong as the session is rich. This character's
# arrival square is refused, so the session proves the prompt STAYS AWAY and
# never proves it still ARRIVES when it should. A session whose arrival square
# is open AND dangerous would close that gap; walking to another of the four
# down staircases on the level was tried and the walk is interrupted by
# monsters and by prompts of its own. What holds the other half up meanwhile
# is that the test now used is the terrain's own EV_MON_CONSIDER -- the same
# expression Move.cpp:477 uses to ask a walking player "Confirm enter the deep
# water?", which a plain seeded session still produces on demand.
#
# THE FIXTURE. The save is Brian's own character, copied while he played on
# 2026-08-21 and recorded in bd inc-wcf. It is a v0 save pinned by sha1, so
# it loads through the v0 reader forever -- do NOT "helpfully" -convert it,
# that would change the bytes and every assertion below rests on them.
# It is not in the repository: it is
# 900KB of binary and it belongs to him. Point INCURSION_WCF_SAVE at a copy if
# it lives somewhere else. Without it this check is INCONCLUSIVE, never a pass
# and never a failure -- a session that never happened says nothing about the
# defect, which is the mistake of inc-loa.3.
#
# The staged copy is what the session plays. The original is never opened by
# the game, only read by cp, so a run cannot damage it.
#
# Usage: tools/check_stair_warn.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SAVE="${INCURSION_WCF_SAVE:-/Users/brianhill/Scripts/incursion-repro-stairwall/Furious_Fox.sav}"
WANT_SHA1="b868277dbf5a78b016685367012d8c558d03905a"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

[ -f "$SAVE" ] || {
    echo "INCONCLUSIVE: the repro save is not at $SAVE."
    echo "              bd inc-wcf records where it came from. Point"
    echo "              INCURSION_WCF_SAVE at a copy to run this check."
    exit 2
}

GOT_SHA1="$(shasum "$SAVE" | awk '{print $1}')"
[ "$GOT_SHA1" = "$WANT_SHA1" ] || {
    echo "INCONCLUSIVE: $SAVE is not the file bd inc-wcf recorded."
    echo "              want sha1 $WANT_SHA1"
    echo "              got  sha1 $GOT_SHA1"
    echo "              Every assertion below depends on this character"
    echo "              standing on the down staircase at (74,70)."
    exit 2
}

RUN="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-stair-warn"
mkdir -p "$RUN/save"
cp "$SAVE" "$RUN/save/Furious_Fox.sav"

INCURSION_STAIR_WARN_PROBE=1 INCURSION_RUN_DIR="$RUN" \
    tools/headless.sh tools/keys/stair-warn.keys 1 > "$RUN/harness.out" 2>&1

SCREENS="$RUN/logs/screens"
LOADED="$SCREENS/0001-loaded.txt"
LAST="$(ls "$SCREENS" 2>/dev/null | sort | tail -1)"

# A. did the session get as far as the staircase?
[ -f "$LOADED" ] || {
    echo "INCONCLUSIVE: the character never loaded. Run dir: $RUN"
    exit 2
}
grep -q "020m" "$LOADED" || {
    echo "INCONCLUSIVE: the restored character is not on depth 2, so the"
    echo "              staircase this check descends is not under her."
    echo "              Run dir: $RUN"
    exit 2
}

fails=0

# B. the prompt itself. Judged from the screens and not from the probe log,
#    because a build that predates the probe writes no log at all and must
#    still be able to fail this.
warned="$(grep -l "Confirm unsafe action" "$SCREENS"/*.txt 2>/dev/null | head -1)"
if [ -n "$warned" ]; then
    echo "FAIL: the descent still asks the player to confirm an unsafe action."
    echo "      On this staircase the square the player would keep is solid, so"
    echo "      MoveDepth refuses it and lands her on a random open square"
    echo "      instead -- the terrain the message names is one she can never"
    echo "      arrive on. This is inc-wcf. The message was:"
    grep -h "Confirm unsafe action" "$warned" | sed 's/^/        /'
    fails=$((fails + 1))
fi

# C. the rule, recomputed from the facts the probe recorded.
LOG="$RUN/logs/stairwarn.log"
lines=0
if [ -f "$LOG" ]; then
    while read -r line; do
        case "$line" in descend*) ;; *) continue ;; esac
        lines=$((lines + 1))
        usable="$(echo "$line" | sed -n 's/.*usable=\([0-9]*\).*/\1/p')"
        unsafe="$(echo "$line" | sed -n 's/.*unsafe=\([0-9]*\).*/\1/p')"
        asked="$(echo "$line" | sed -n 's/.*asked=\([0-9]*\).*/\1/p')"
        if [ "$asked" != "$unsafe" ]; then
            echo "FAIL: the player was asked when the terrain did not call the"
            echo "      square unsafe, or was not asked when it did: $line"
            fails=$((fails + 1))
        fi
        if [ "$unsafe" = "1" ] && [ "$usable" = "0" ]; then
            echo "FAIL: a square MoveDepth refuses was judged unsafe. A refused"
            echo "      square is re-rolled at random after this point, so"
            echo "      nothing about it can be named: $line"
            fails=$((fails + 1))
        fi
    done < "$LOG"
fi

# D. did she actually go down?
depth="$(grep -ho "0[0-9][0-9]m" "$SCREENS/$LAST" 2>/dev/null | head -1)"
if [ "$depth" != "030m" ]; then
    echo "FAIL: the character is at ${depth:-an unknown depth} after pressing"
    echo "      '>' on a down staircase, not 030m. The descent did not happen."
    fails=$((fails + 1))
fi

echo "loaded on depth 2, pressed '>' on the down staircase at (74,70)"
if [ -f "$LOG" ]; then
    echo "$lines descent(s) recorded by the probe:"
    grep "^descend" "$LOG" | sed 's/^/  /'
else
    echo "no probe log: this build carries no INCURSION_STAIR_WARN_PROBE, so"
    echo "only the screens were read"
fi
echo "depth after the descent: ${depth:-unknown}"
echo "note: this session's arrival square is refused by MoveDepth, so it does"
echo "      not exercise a warning that SHOULD fire. See the ponytail note in"
echo "      this script."

if [ "$fails" -gt 0 ]; then
    echo
    echo "Run dir: $RUN"
    exit 1
fi

echo "PASS"
exit 0
