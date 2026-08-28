#!/bin/bash
# Regression check for the Sanctuary defect, inc-r1e6: the spell never ended
# when the warded creature attacked, so a priest could hold it while swinging.
#
# THE DEFECT. lib/pspells.irh's Sanctuary registers three TRAP_EVENT stati on
# landing -- EVICTIM(EV_STRIKE), EV_EFFECT and EV_MAGIC_STRIKE -- and defines
# handlers for EVICTIM(EV_STRIKE), EV_STRIKE and EV_MAGIC_STRIKE. The lists do
# not match: EV_STRIKE has a handler and no trap, EV_EFFECT a trap and no
# handler. src/Event.cpp:322-340 calls a trap's effect only when META(S->Mag)
# equals the event being thrown, so the one handler that removes the spell when
# its holder attacks could never run. The spell's own Desc promises "This
# protection ceases if you take any directly hostile action against another
# creature", and the 3.5 SRD says the subject cannot attack without breaking
# the spell.
#
# THE ORACLE is the game's Sanctuary indicator on the map screen's status line.
# src/Term.cpp:185 walks the player's live stati on every redraw and prints the
# name of any T_TEFFECT stati whose effect carries EF_SHOWNAME; Sanctuary
# carries it. The word is therefore on screen for exactly as long as the player
# holds the stati.
#
# WHY THE ORACLE CANNOT BE FAKED. A key script sends keystrokes and nothing
# else -- it cannot write to the screen, and the indicator is not a message
# that could linger in the message window after the state behind it changed.
# The check reads the same word off three screens from one session, and a
# passing run needs it PRESENT on the first two and ABSENT on the third, so
# neither a build that never applies Sanctuary nor one that drops it on any
# passing turn can reach a pass:
#
#   after-cast       the spell has just landed
#   after-nonattack  a summon and three searches later -- the control
#   after-strike     one melee blow later
#
# The middle screen is the control and the reason this check has three
# photographs rather than two. It is also the rule: the SRD lets the warded
# creature "use nonattack spells or otherwise act" without losing the spell.
#
# Exit 0 pass, 1 the defect is present, 2 the session measured nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }

SEED="${1:-4}"
OUT="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh tools/keys/sanctuary-strike.keys "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
if echo "$OUT" | grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL'; then
    echo "INCONCLUSIVE: the run did not complete its measurement"; echo "$OUT"; exit 2
fi

CAST="$RUN/logs/screens/0001-after-cast.txt"
BEFORE="$RUN/logs/screens/0002-traps-before.txt"
CONTROL="$RUN/logs/screens/0003-after-nonattack.txt"
AFTER="$RUN/logs/screens/0004-after-strike.txt"
LOG="$RUN/logs/screens/0005-strike-log.txt"
TRAPS="$RUN/logs/screens/0006-traps-after.txt"
for f in "$CAST" "$BEFORE" "$CONTROL" "$AFTER" "$LOG" "$TRAPS"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: missing measurement screen $f"; exit 2; }
done

# Game time either side of the control, read off the dump headers. A control
# that spent no turns is not a control.
_turn() { sed -n '1s/.*turn \([0-9]*\).*/\1/p' "$1"; }
T_CAST="$(_turn "$CAST")"; T_CTRL="$(_turn "$CONTROL")"; T_HIT="$(_turn "$AFTER")"

SHOWN_CAST=0;  grep -q 'Sanctuary' "$CAST"    && SHOWN_CAST=1
SHOWN_CTRL=0;  grep -q 'Sanctuary' "$CONTROL" && SHOWN_CTRL=1
SHOWN_AFTER=0; grep -q 'Sanctuary' "$AFTER"   && SHOWN_AFTER=1
STRUCK=0;      grep -q 'Attack: 1d20' "$LOG"  && STRUCK=1

echo "Sanctuary, seed $SEED:"
echo "  traps registered: $(grep -o 'TRAP EVENT from SS MISC (Val:[0-9-]* Mag:[0-9-]*' "$BEFORE" | sed 's/.*Mag://' | tr '\n' ' ')"
echo "  indicator after the cast   (turn $T_CAST): $SHOWN_CAST"
echo "  indicator after a non-attack (turn $T_CTRL): $SHOWN_CTRL"
echo "  indicator after the strike (turn $T_HIT): $SHOWN_AFTER"
echo "  the session really struck: $STRUCK"
echo "  traps left afterwards: $(grep -c 'TRAP EVENT from SS MISC' "$TRAPS")"

if [ "$STRUCK" != 1 ]; then
    echo "INCONCLUSIVE: the message log carries no attack roll, so the warded"
    echo "              creature never struck and nothing was measured."; exit 2
fi
if [ "$SHOWN_CAST" != 1 ]; then
    echo "INCONCLUSIVE: the session never got Sanctuary up, so its absence"
    echo "              after the strike says nothing."; exit 2
fi
if [ "$T_CTRL" = "$T_CAST" ]; then
    echo "INCONCLUSIVE: no game time passed during the control, so the control"
    echo "              did not test that an ordinary turn keeps the spell."; exit 2
fi
if [ "$SHOWN_CTRL" != 1 ]; then
    echo "INCONCLUSIVE: the control lost Sanctuary without an attack, so this"
    echo "              session cannot attribute a later loss to the strike."; exit 2
fi
if [ "$SHOWN_AFTER" != 0 ]; then
    echo "FAIL: the warded creature struck a goblin and kept Sanctuary (inc-r1e6)."
    exit 1
fi
echo "PASS: Sanctuary survives an ordinary turn and ends on the holder's own blow"
