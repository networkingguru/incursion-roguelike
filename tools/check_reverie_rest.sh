#!/bin/bash
# gate: live
# Guards inc-mknk: the elf race text promises that Reverie gives (a) a
# drastically reduced chance of rest encounters and (b) no surprise when an
# encounter happens. The ruling: in Player::Rest, a Reverie character's Chance
# is divided by 4 (integer division) right after RestEncounterChance, and
# Reverie sets wakeSafely so the character is not put to SLEEPING with a
# Timeout of 60. RestEncounterChance itself MUST NOT change (SpendHours and
# src/Skills.cpp call it and keep the full chance).
#
# THE ORACLE is INCURSION_REVERIE_PROBE, which arms Player::ReverieRestProbe()
# (src/Player.cpp). It drives the REAL Player::Rest with Reverie off, then on,
# twice: once with the roll forced high (no encounter) to read the final
# Chance, once with the roll forced to -1 (an encounter) to read the wake
# state. It narrates through Error():
#   REVERIE_PROBE raw reverie=<0|1> chance=<n>        RestEncounterChance itself
#   REVERIE_PROBE rest roll=<n> raw=<n> chance=<n> reverie=<0|1>
#   REVERIE_PROBE wake reverie=<0|1> sleeping=<0|1> timeout=<n>
# If the probe finds no hostile out of sight it forces raw Chance to 100 so the
# division is visible; "rest raw=" is that forced value.
#
# Usage: tools/check_reverie_rest.sh  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat

export INCURSION_REVERIE_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav

check_run tools/keys/load-char-sheet.keys 4

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 \
    "the run logged nothing at all. The probe reports through Error()," \
    "so an empty log means it never ran."

CLEAN="$(grep -v '^    ' "$LOG")"
P() { printf '%s\n' "$CLEAN" | grep "REVERIE_PROBE $1" | head -1; }
F() { echo "$1" | grep -oE "$2=-?[0-9]+" | sed "s/$2=//"; }

RAW0="$(P 'raw reverie=0')";   RAW1="$(P 'raw reverie=1')"
C0="$(P 'rest roll=1000 .*reverie=0')"; C1="$(P 'rest roll=1000 .*reverie=1')"
W0="$(P 'wake reverie=0')";    W1="$(P 'wake reverie=1')"

[ -n "$RAW0" ] && [ -n "$RAW1" ] && [ -n "$C0" ] && [ -n "$C1" ] && \
    [ -n "$W0" ] && [ -n "$W1" ] || _check_die 2 \
    "the probe did not log its raw, rest and wake lines for both Reverie" \
    "settings. Does this build contain Player::ReverieRestProbe, is it called" \
    "from Game::Play (src/Main.cpp), and did Player::Rest abort (hostile in" \
    "sight)?"

RAW0V="$(F "$RAW0" chance)"; RAW1V="$(F "$RAW1" chance)"
CH0="$(F "$C0" chance)"; CH1="$(F "$C1" chance)"; IN0="$(F "$C0" raw)"; IN1="$(F "$C1" raw)"
SL0="$(F "$W0" sleeping)"; SL1="$(F "$W1" sleeping)"
TO0="$(F "$W0" timeout)"; TO1="$(F "$W1" timeout)"

for v in RAW0V RAW1V CH0 CH1 IN0 IN1 SL0 SL1 TO0 TO1; do
    [ -n "${!v}" ] || _check_die 2 "could not parse $v out of the probe lines."
done

FAIL=0
if [ "$RAW0V" -ne "$RAW1V" ]; then
    echo "FAIL: RestEncounterChance changed with Reverie ($RAW0V vs $RAW1V)."
    echo "      the cut belongs in Player::Rest, not in RestEncounterChance."
    FAIL=1
fi
if [ "$IN0" -ne "$IN1" ] || [ "$IN0" -le 3 ]; then
    echo "FAIL: the two rests did not start from the same raw Chance >= 4"
    echo "      ($IN0 vs $IN1), so the division cannot be read."
    _check_die 2 "inconclusive: unequal or too-small raw Chance."
fi
if [ "$CH1" -ne $((CH0 / 4)) ]; then
    echo "FAIL: Reverie rest Chance is $CH1; expected $((CH0 / 4)) (a quarter of the"
    echo "      non-Reverie $CH0, integer division)."
    FAIL=1
fi
if [ "$SL0" -ne 1 ]; then
    echo "FAIL: the non-Reverie control was not put to SLEEPING after an"
    echo "      interrupted rest (sleeping=$SL0); the probe is not reaching that branch."
    _check_die 2 "inconclusive: control did not sleep."
fi
if [ "$SL1" -ne 0 ] || [ "$TO1" -ge 60 ]; then
    echo "FAIL: the Reverie character did not wake safely after an interrupted"
    echo "      rest (sleeping=$SL1 timeout=$TO1)."
    FAIL=1
fi

echo
echo "--- what the probe logged ---"
printf '%s\n' "$RAW0" "$RAW1" "$C0" "$C1" "$W0" "$W1"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
echo
echo "PASS: Reverie Chance $CH1 = $CH0 / 4; Reverie wakes safely (sleeping=$SL1" \
     "timeout=$TO1) where the control sleeps (timeout=$TO0); raw unchanged ($RAW0V)."
exit 0
