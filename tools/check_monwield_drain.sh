#!/bin/bash
# gate: live
# A monster that wields a wrong-alignment weapon takes two real levels. (bd inc-qaav4)
#
# ORACLE: INCURSION_MONWIELD_PROBE arms MonWieldProbe() (src/MonWieldProbe.cpp), run once at the
# top of Game::Play. No wizard path makes a monster wield a chosen item, so the probe does: it
# gives a troll and a kobold (CR below 2) an ALIGNMENT stati of good, creates an unholy
# long sword, and throws EV_WIELD into SL_WEAPON. One Error() line per monster:
#   MONWIELD_PROBE survivor before=<n> after=<n> died=<0|1>
#   MONWIELD_PROBE victim   before=<n> after=<n> died=<0|1>
# TWO PROPERTIES: the troll has after == before - 2 and died=0; the kobold has died=1.
#
# fact: monsters -- troll and kobold made by the probe; alignment forced by ALIGNMENT stati
# fact: the weapon -- long sword + WQ_UNHOLY made by the probe
# fact: settings -- options-2026-08-22.dat (CHECK_OPTIONS)
# fact: the player's position -- the probe places monsters with PlaceNear; the log line reads only stati and death
# fact: dice -- none read; a stati sum and a death flag
#
# Usage: tools/check_monwield_drain.sh [--prove-red]   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
SEED=3
KEYS=tools/keys/dive.keys

# The mutation removes the drain: Monster::Wield no longer lowers the stati.
check_mutation src/Inv.cpp \
'theGame->InPlay() && opposesAlignmentOf(e.EItem)' \
'false && opposesAlignmentOf(e.EItem)'

export INCURSION_MONWIELD_PROBE=1
check_run "$KEYS" "$SEED"

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 "the run logged nothing at all; the probe reports through Error()."

line() { grep -v '^    ' "$LOG" | grep "MONWIELD_PROBE $1 before" | head -1; }
S="$(line survivor)"
V="$(line victim)"
[ -n "$S" ] && [ -n "$V" ] || _check_die 2 \
    "the probe did not log both monsters (or said INCONCLUSIVE):" \
    "$(grep -v '^    ' "$LOG" | grep MONWIELD_PROBE)"

val() { echo "$1" | grep -oE "$2=-?[0-9]+" | sed "s/$2=//"; }
SB="$(val "$S" before)"; SA="$(val "$S" after)"; SD="$(val "$S" died)"
VD="$(val "$V" died)"
[ -n "$SB" ] && [ -n "$SA" ] && [ -n "$SD" ] && [ -n "$VD" ] || _check_die 2 "could not parse: $S / $V"

FAIL=0
if [ "$SA" -ne $((SB - 2)) ]; then
    echo "FAIL: the troll's neglev total did not fall by 2 (before=$SB after=$SA)."
    FAIL=1
fi
if [ "$SD" -ne 0 ]; then
    echo "FAIL: the troll died of two levels."
    FAIL=1
fi
if [ "$VD" -ne 1 ]; then
    echo "FAIL: the low-CR kobold survived the two levels (died=$VD)."
    FAIL=1
fi

echo
echo "--- what the probe logged ---"
echo "$S"
echo "$V"

[ "$FAIL" -eq 0 ] || exit 1
echo
echo "PASS: a wrong-alignment wield took two levels from the troll and killed the kobold"
