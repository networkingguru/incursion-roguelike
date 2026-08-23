#!/bin/bash
# Does the equipment-save message name the character, and reach him? (bd inc-473)
#
# WHAT WENT WRONG. A monster with an A_DEQU attack answers a blow by attacking
# the striker's weapon. If the striker makes the Reflex save the handler prints
# a message and returns. Brian played this on 2026-08-15 and read:
#
#     the orcish bastard sword +1 protects its orcish bastard sword +1
#
# ETarget and EVictim are one event slot read through two macros
# (inc/Events.h:214-215). The handler set the item as the damage target so the
# EV_DAMAGE rethrow would hit the item and not its owner -- which is right --
# and thereby erased the owner from the slot the message reads. So the line
# named the item twice, and, worse, VPrint delivered the first-person half to
# the ITEM, whose Thing::__IPrint is an empty virtual. The character was told
# nothing and got the third-person line meant for onlookers instead.
#
# THE ORACLE, and why the screen settles the routing too. VPrint gives msg1
# only to e.EVictim and msg2 only to a player who is NOT e.EVictim
# (src/Message.cpp:621). In a one-player session the two strings therefore
# cannot both reach the same screen. Reading "You avoid harm to your <item>."
# on the player's own screen is proof that he is e.EVictim again; reading "The
# <item> protects its <item>." is proof that he is not. A check that only
# grepped for better wording would not have separated those two.
#
# WHY THE PROBE BUILD. The message prints only on a successful save, and the
# brown pudding's A_DEQU is DC 19, so an unforced script would be waiting on a
# die. -DDEQU_PROBE adds one env-gated disjunct to the save test and nothing
# else; the shipped binary does not contain it.
#
# Proved RED before it was believed: built with the ETarget assignment back in
# its original place, this run put "protects its orcish knife +1" on 6 of 6
# strike screens and the first-person line on 0 of 6. With the assignment moved
# below the save, 6 of 6 and 0 of 6 the other way round.
#
# Usage: tools/check_dequ_save_message.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${DEQU_SEED:-5}"
KEYS=tools/keys/dequ-save-message.keys
BIN="${DEQU_BIN:-./incursion-dequ}"

GOOD="You avoid harm to your"
BAD="protects its"

[ -f "$KEYS" ] || { echo "no such key script: $KEYS"; exit 2; }

[ -x "$BIN" ] || {
    echo "$BIN not built. Forcing the save is only possible in the probe build:"
    echo "  BACKEND=posix EXTRA_CXXFLAGS=-DDEQU_PROBE OUT=incursion-dequ ./build_macos.sh"
    exit 2
}

# The live Options.Dat, deliberately, and not the pinned gate file: seed 5 under
# the gate settings does not reach the wizard menu with these keystrokes, and
# tools/check_spook_ally.sh -- the script this one's chargen and summon sequence
# is taken from -- runs the same way for the same reason. Nothing here compares
# one run against a stored screen, so a settings change cannot silently move the
# answer; it can only stop the run reaching the pudding, which the guards below
# report as a failure rather than a pass.
OUT="$(INCURSION_DEQU_FORCE_SAVE=1 INCURSION_BIN="$BIN" \
       tools/headless.sh "$KEYS" "$SEED" 2>&1 < /dev/null)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"

# A session that measured nothing must never read as a pass -- that is inc-loa.3.
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi

SCREENS="$(ls "$RUN"/logs/screens/*-strike-*.txt 2>/dev/null)"
if [ -z "$SCREENS" ]; then
    echo "FAIL: the session dumped no strike screens under $RUN/logs/screens"
    echo "$OUT" | grep -E '^(ended|death|stuck-prompt):'
    exit 1
fi

# Second guard: the pudding has to have been summoned at all. Without this a
# run whose wizard menu moved would dump six screens of an empty cave and pass
# every assertion below by never printing either string.
if ! grep -lq "brown pudding" $SCREENS; then
    echo "FAIL: no strike screen mentions a brown pudding, so nothing was struck"
    echo "      $RUN/logs/screens"
    exit 1
fi

N=$(echo "$SCREENS" | wc -l | tr -d ' ')
NGOOD=$(grep -l "$GOOD" $SCREENS 2>/dev/null | wc -l | tr -d ' ')
NBAD=$(grep -l "$BAD" $SCREENS 2>/dev/null | wc -l | tr -d ' ')

echo "  strike screens: $N   first-person: $NGOOD   third-person: $NBAD"

# Third guard, and the one that stops this check being unfailable: the save
# message has to have printed SOMEWHERE. If the player missed every swing, or
# the response attack never fired, neither string appears and an assertion of
# the form "the bad string is absent" would pass on nothing at all.
if [ "$NGOOD" -eq 0 ] && [ "$NBAD" -eq 0 ]; then
    echo "FAIL: no equipment-save message was printed on any strike screen."
    echo "      Either no blow landed or the A_DEQU response never ran, so this"
    echo "      run proves nothing about the message. See $RUN/logs/screens"
    exit 1
fi

if [ "$NBAD" -ne 0 ]; then
    echo "FAIL: the message still names the item where the creature belongs,"
    echo "      and so still goes to the wrong recipient."
    grep -ho ".\{0,40\}$BAD.\{0,30\}" $SCREENS | head -1
    echo "      $RUN/logs/screens"
    exit 1
fi

if [ "$NGOOD" -ne "$N" ]; then
    echo "FAIL: only $NGOOD of $N strike screens carry the first-person line."
    echo "      $RUN/logs/screens"
    exit 1
fi

echo "  ok: $(grep -ho "$GOOD.\{0,25\}" $SCREENS | head -1)"
echo "PASS: the character is told about his own equipment, in his own words"
echo "      ($RUN/logs/screens)"
exit 0
