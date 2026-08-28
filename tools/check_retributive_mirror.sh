#!/bin/bash
# Regression check for the Retributive Mirror reflection divisor, inc-tek.8.7
# (PA-07-F5).
#
# THE DEFECT. lib/pspells.irh declared the Retributive Mirror EA_INFLICT effect
# with a META(PRE(EVICTIM(EV_DAMAGE))) handler that computed the reflected
# damage as `bonus = e.vDmg / 5`, while the effect's own Desc promises "one third
# of all damage dealt to you (round down) is reflected back to the attacker".
# The divisor 5 paid one fifth, not the one third the prose advertises.
# Retributive Mirror is an Incursion invention with no D&D twin, so its own Desc
# is the only reference and the divisor MUST be 3.
#
# THE ORACLE is the `bonus = e.vDmg / N` assignment in the handler. That line is
# the only `bonus = e.vDmg` in the file, so it is identified without ambiguity.
# The neighbouring `dmg = e.vDmg / 4` (a different effect) never matches because
# it assigns `dmg`, not `bonus`.
#
# WHY THE ORACLE CANNOT BE FAKED. It reads the tracked source directly, so it
# proves the shipped data and not a transient screen. It fails red if the
# divisor is 5, and only passes on 3.
#
# Exit 0 pass, 1 the defect is present (still / 5 or some other value), 2 the
# assignment could not be found -- the handler moved or was renamed.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/lib/pspells.irh"

[ -f "$FILE" ] || { echo "FAIL(2): $FILE is missing; nothing was examined"; exit 2; }

# The Retributive Mirror reflection assignment, and only it.
LINE="$(grep -nE 'bonus[[:space:]]*=[[:space:]]*e\.vDmg[[:space:]]*/[[:space:]]*[0-9]+' "$FILE")"

COUNT="$(printf '%s\n' "$LINE" | grep -c . )"
if [ "$COUNT" -ne 1 ]; then
    echo "FAIL(2): expected exactly one 'bonus = e.vDmg / N' line, found $COUNT."
    echo "         The handler moved or was renamed. Re-point this check before trusting it."
    printf '%s\n' "$LINE" | sed 's/^/    | /'
    exit 2
fi

# The divisor after the slash.
DIV="$(printf '%s\n' "$LINE" | grep -oE 'e\.vDmg[[:space:]]*/[[:space:]]*[0-9]+' | grep -oE '[0-9]+$')"

if [ "$DIV" = "3" ]; then
    echo "PASS: Retributive Mirror reflects e.vDmg / 3, the one third its Desc promises."
    exit 0
fi

echo "FAIL(1): Retributive Mirror reflects e.vDmg / ${DIV:-<unreadable>}, not the one third (/ 3) its Desc promises."
echo "         Fix the divisor in lib/pspells.irh (inc-tek.8.7)."
printf '%s\n' "$LINE" | sed 's/^/    | /'
exit 1
