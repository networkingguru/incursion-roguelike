#!/bin/bash
# Regression check for the Zeal defect, inc-tek.31: the paladin spell never
# ended when its holder attacked a creature other than the one the spell chose,
# so a paladin under Zeal could swing at anybody and keep it.
#
# THE DEFECT. lib/pspells.irh's Zeal is a copy of Sanctuary and carried
# Sanctuary's defect unchanged. It registers three TRAP_EVENT stati on landing
# -- EVICTIM(EV_STRIKE), EV_EFFECT and EV_MAGIC_STRIKE -- and defines handlers
# for EVICTIM(EV_STRIKE), EV_STRIKE and EV_MAGIC_STRIKE. The lists do not
# match: EV_STRIKE has a handler and no trap, EV_EFFECT a trap and no handler.
# src/Event.cpp:322-340 calls a trap's effect only when META(S->Mag) equals the
# event being thrown, so the one handler that removes the spell when its holder
# attacks could never run. The spell's own Desc promises "If the paladin
# attacks any other target, the effect ceases -- the target is free to attack
# him in turn."
#
# THE ORACLE is the game's Zeal indicator on the map screen's status line.
# src/Term.cpp:185 walks the player's live stati on every redraw and prints the
# name of any T_TEFFECT stati whose effect carries EF_SHOWNAME; Zeal carries
# it. The word is therefore on screen for exactly as long as the paladin holds
# the stati.
#
# WHY THE ORACLE CANNOT BE FAKED. A key script sends keystrokes and nothing
# else -- it cannot write to the screen, and the indicator is not a message
# that could linger in the message window after the state behind it changed.
# The check reads the same word off four screens from one session:
#
#   after-cast       the spell has just landed          -- MUST be shown
#   after-nonattack  three searches later               -- MUST be shown
#   after-chosen     one blow at the CHOSEN target      -- MUST be shown
#   after-other      one blow at the second babau       -- MUST be gone
#
# THE THIRD READING IS WHY THIS CHECK IS NOT JUST A COPY OF THE SANCTUARY ONE.
# Zeal adds an exemption that Sanctuary has no need of: each of its three
# handlers opens by comparing the creature being struck against a handle the
# cast stored in an EFF_FLAG1 stati, and returns without ending the spell when
# they are the same. That is the whole point of the spell -- a paladin who lost
# Zeal the moment he swung at the target he chose would have cast it for
# nothing. A check that read only "Zeal ends on a blow" would pass a build in
# which that exemption had been broken.
#
# Exit 0 pass, 1 the defect is present (or its exemption is broken), 2 the
# session measured nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }

SEED="${1:-4}"
OUT="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh tools/keys/zeal-strike.keys "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
if echo "$OUT" | grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL'; then
    echo "INCONCLUSIVE: the run did not complete its measurement"; echo "$OUT"; exit 2
fi

CAST="$RUN/logs/screens/0001-after-cast.txt"
BEFORE="$RUN/logs/screens/0002-traps-before.txt"
CONTROL="$RUN/logs/screens/0003-after-nonattack.txt"
CHOSEN="$RUN/logs/screens/0004-after-chosen.txt"
CHOSENLOG="$RUN/logs/screens/0005-chosen-log.txt"
OTHER="$RUN/logs/screens/0006-after-other.txt"
OTHERLOG="$RUN/logs/screens/0007-other-log.txt"
TRAPS="$RUN/logs/screens/0008-traps-after.txt"
for f in "$CAST" "$BEFORE" "$CONTROL" "$CHOSEN" "$CHOSENLOG" "$OTHER" "$OTHERLOG" "$TRAPS"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: missing measurement screen $f"; exit 2; }
done

# Game time at each reading, off the dump headers. A reading that spent no
# turns since the one before it did not measure a turn's worth of anything.
_turn() { sed -n '1s/.*turn \([0-9]*\).*/\1/p' "$1"; }
T_CAST="$(_turn "$CAST")"; T_CTRL="$(_turn "$CONTROL")"
T_CHOSEN="$(_turn "$CHOSEN")"; T_OTHER="$(_turn "$OTHER")"

SHOWN_CAST=0;   grep -q 'Zeal' "$CAST"    && SHOWN_CAST=1
SHOWN_CTRL=0;   grep -q 'Zeal' "$CONTROL" && SHOWN_CTRL=1
SHOWN_CHOSEN=0; grep -q 'Zeal' "$CHOSEN"  && SHOWN_CHOSEN=1
SHOWN_OTHER=0;  grep -q 'Zeal' "$OTHER"   && SHOWN_OTHER=1

# The message log is cumulative, so the count of attack rolls on the second log
# has to be larger than the count on the first. One blow that landed twice in
# the log, or a second blow that never happened, both fail this.
ROLLS_CHOSEN="$(grep -c 'Attack: 1d20' "$CHOSENLOG")"
ROLLS_OTHER="$(grep -c 'Attack: 1d20' "$OTHERLOG")"

echo "Zeal, seed $SEED:"
echo "  traps registered: $(grep -o 'TRAP EVENT from SS MISC (Val:[0-9-]* Mag:[0-9-]*' "$BEFORE" | sed 's/.*Mag://' | tr '\n' ' ')"
echo "  indicator after the cast          (turn $T_CAST): $SHOWN_CAST"
echo "  indicator after a non-attack      (turn $T_CTRL): $SHOWN_CTRL"
echo "  indicator after the CHOSEN target (turn $T_CHOSEN): $SHOWN_CHOSEN"
echo "  indicator after the OTHER babau   (turn $T_OTHER): $SHOWN_OTHER"
echo "  attack rolls in the log: $ROLLS_CHOSEN then $ROLLS_OTHER"
echo "  traps left afterwards: $(grep -c 'TRAP EVENT from SS MISC' "$TRAPS")"

if [ "$ROLLS_CHOSEN" -lt 1 ]; then
    echo "INCONCLUSIVE: the message log carries no attack roll for the first"
    echo "              blow, so the paladin never struck his chosen target."; exit 2
fi
if [ "$ROLLS_OTHER" -le "$ROLLS_CHOSEN" ]; then
    echo "INCONCLUSIVE: the log gained no attack roll for the second blow, so"
    echo "              the paladin never struck the other creature."; exit 2
fi
if [ "$SHOWN_CAST" != 1 ]; then
    echo "INCONCLUSIVE: the session never got Zeal up, so its absence after a"
    echo "              blow says nothing."; exit 2
fi
if [ "$T_CTRL" = "$T_CAST" ]; then
    echo "INCONCLUSIVE: no game time passed during the control, so the control"
    echo "              did not test that an ordinary turn keeps the spell."; exit 2
fi
if [ "$T_OTHER" = "$T_CHOSEN" ]; then
    echo "INCONCLUSIVE: no game time passed between the two blows, so the two"
    echo "              readings are one reading."; exit 2
fi
if [ "$SHOWN_CTRL" != 1 ]; then
    echo "INCONCLUSIVE: the control lost Zeal without an attack, so this session"
    echo "              cannot attribute a later loss to a blow."; exit 2
fi
if [ "$SHOWN_CHOSEN" != 1 ]; then
    echo "FAIL: the paladin struck the very target Zeal chose and lost the spell."
    echo "      The exemption -- the EFF_FLAG1 handle each handler compares"
    echo "      against -- is broken, which makes the spell useless (inc-tek.31)."
    exit 1
fi
if [ "$SHOWN_OTHER" != 0 ]; then
    echo "FAIL: the paladin struck a creature Zeal did not choose and kept the"
    echo "      spell (inc-tek.31)."
    exit 1
fi
echo "PASS: Zeal survives an ordinary turn and a blow at its chosen target, and"
echo "      ends on a blow at anything else"
