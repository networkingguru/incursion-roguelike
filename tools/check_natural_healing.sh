#!/bin/bash
# gate: live
# Waking natural healing: every game hour a living creature below full HP
# regains 1/16 of the full-rest amount, and a Character trains CON for each
# HP healed. (bd inc-wrfz, ruling inc-g69h row 2)
#
# THE ORACLE is INCURSION_NATHEAL_PROBE, which arms Character::NatHealProbe()
# (src/Create.cpp), run at the top of Game::Play() on the loaded player. For
# one game hour it sets Turn to each of the 300 EV_TURN steps and calls the
# live Creature::DoTurn() once per step, in three cases: no Heal skill, Heal
# ranks, full HP. Each logs "NATHEAL_PROBE case=... X=... hpBefore=...
# hpAfter=... exBefore=... exAfter=...", where X/640 is the hourly HP.
#
# THE PROPERTY: healed == X/640 within 1 HP; the CON exercise total rises by
# exactly the HP healed; full HP heals and exercises nothing.
#
# PROVED RED with --prove-red (the mutation halves the rate). The exercise
# assertion was proved red by hand by removing the Exercise call.
#
# Usage: tools/check_natural_healing.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

SEED=1
KEYS=tools/keys/load-char-sheet.keys

check_mutation src/Creature.cpp \
'            const int32 D = 640 * steps;' \
'            const int32 D = 1280 * steps;'

export INCURSION_NATHEAL_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed1-opt0822.sav

check_run "$KEYS" "$SEED"

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 \
    "the run logged nothing at all. The probe reports through Error()," \
    "so an empty log means it never ran."

CLEAN="$(grep -v '^    ' "$LOG")"

field() { # <line> <name>
    echo "$1" | grep -oE " $2=-?[0-9]+" | head -1 | sed "s/ $2=//"
}

FAIL=0
for c in noheal heal full; do
    LINE="$(printf '%s\n' "$CLEAN" | grep "NATHEAL_PROBE case=$c " | head -1)"
    [ -n "$LINE" ] || _check_die 2 \
        "the probe never logged case $c. Is Character::NatHealProbe() still" \
        "called from Game::Play() (src/Main.cpp), and does this build contain it?"
    X="$(field "$LINE" X)"; MHP="$(field "$LINE" mHP)"
    HB="$(field "$LINE" hpBefore)"; HA="$(field "$LINE" hpAfter)"
    EB="$(field "$LINE" exBefore)"; EA="$(field "$LINE" exAfter)"
    for v in X MHP HB HA EB EA; do
        [ -n "${!v}" ] || _check_die 2 "could not parse $v out of: $LINE"
    done
    HEALED=$((HA - HB)); EX=$((EA - EB))
    eval "X_$c=$X"
    echo "$LINE"
    if [ "$c" = full ]; then
        [ "$HEALED" -eq 0 ] && [ "$EX" -eq 0 ] || {
            echo "FAIL: case full: healed $HEALED HP, exercised $EX (both must be 0)"; FAIL=1; }
        continue
    fi
    [ "$X" -gt 0 ] || _check_die 2 "case $c has X=$X; the fixture cannot measure healing."
    [ $((MHP - 1)) -gt $((X / 640 + 2)) ] || _check_die 2 \
        "case $c: mHP=$MHP is too low; the character would hit full HP mid-hour."
    DIFF=$((HEALED * 640 - X)); [ "$DIFF" -lt 0 ] && DIFF=$((-DIFF))
    if [ "$DIFF" -gt 640 ]; then
        echo "FAIL: case $c: healed $HEALED HP in one hour, formula $X/640"; FAIL=1
    fi
    if [ "$EX" -ne "$HEALED" ]; then
        echo "FAIL: case $c: CON exercise rose by $EX, HP healed $HEALED"; FAIL=1
    fi
done
[ "$X_heal" -gt "$X_noheal" ] || {
    echo "FAIL: Heal ranks did not raise the hourly amount ($X_heal vs $X_noheal)"; FAIL=1; }

[ "$FAIL" -eq 0 ] || exit 1
echo
echo "PASS: one waking hour healed the formula amount (within 1 HP) with and"
echo "      without Heal, trained CON once per HP, and did nothing at full HP."
exit 0
