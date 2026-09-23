#!/bin/bash
# gate: live
# The player mana-regen floor fix must hold up under REAL PLAY, with no
# forced state: cast real spells until mana sits inside the 35-80% band the
# fix cares about, then wait without resting. (bd inc-41kg)
#
# WHY A SECOND CHECK. tools/check_mana_regen_floor.sh proves the formula by
# forcing held mana, spent mana and Concentration directly in C++, so its
# own evidence tier is Traced. This one asks for the same property under
# ordinary keystrokes -- a normal spell cast, a normal wait -- with nothing
# poked into the object. If it also goes red on the un-fixed formula and
# green on the fix, the fix earns Observed.
#
# THE SCRIPT, tools/keys/mana-regen-cast.keys (its own header has the full
# derivation). Henk, the seed-4 orc-mage-seed4-gate fixture (Concentration
# +3), casts Burning Hands 35 times aimed away from himself into open floor
# -- deterministic, no lasting hold on mana (no EF_PERSISTANT/EF_LOSEMANA),
# so held mana stays 0 throughout. That reliably lands current mana at
# 43/72 = 59.7% of the pool, inside 35-80% with margin either side. Three
# searches then buy roughly 75 turns without resting (KY_CMD_SEARCH grants
# ACTING for 25 rounds and keeps going on its own -- src/Player.cpp), and a
# normal Save and Continue at the end reaches the same read-only channel
# check_xp_drain.sh and check_quiet_lookup.sh use for other probes, plus
# src/Dump.cpp's explicit "spent S, held H" line via tools/dump_save.sh, so
# held mana is READ, not assumed.
#
# THE PROPERTY. At 59.7% of the pool, with Concentration close to nothing:
#   fixed formula, floor max(80-2*3,35)=74%:  59.7 < 74, so regen is
#     blocked and mana after the wait equals mana after the casts.
#   old formula, floor min(35+2*3,80)=41%:    59.7 >= 41, so regen runs and
#     mana after the wait is HIGHER than mana after the casts.
# So this check goes red on the old formula (a rise where none should be)
# and green on the new one (no rise).
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2), the same
# mutation tools/check_mana_regen_floor.sh declares against the same site.
#
# Usage: tools/check_mana_regen_cast.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat

SEED=4
KEYS=tools/keys/mana-regen-cast.keys

# The mutation this check defends: the base-code condition, read directly off
# Creature::DoTurn before this fix. Same site tools/check_mana_regen_floor.sh
# declares; declared again here so this check proves itself on its own.
check_mutation src/Creature.cpp \
'        if (!isPlayer() || cMana() >= ((nhMana()*ManaRegenFloor())/100)) {' \
'        if (!isPlayer() || cMana() >= ((nhMana()*min(35+SkillLevel(SK_CONCENT)*2,80))/100)) {'

export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav

check_run "$KEYS" "$SEED"

# Three on-screen readings, plus the authoritative save dump for the final
# one. No env probe and no forced state anywhere in this check.
ARRIVAL_FILE="$(ls "$CHECK_RUN"/logs/screens/*arrival*.txt 2>/dev/null | head -1)"
CASTS_FILE="$(ls "$CHECK_RUN"/logs/screens/*after-casts*.txt 2>/dev/null | head -1)"
WAIT_FILE="$(ls "$CHECK_RUN"/logs/screens/*after-wait*.txt 2>/dev/null | head -1)"

[ -n "$ARRIVAL_FILE" ] && [ -n "$CASTS_FILE" ] && [ -n "$WAIT_FILE" ] || _check_die 2 \
    "one of the three screen dumps (arrival, after-casts, after-wait) is" \
    "missing under $CHECK_RUN/logs/screens. Did the key script reach that far?"

_mana_of() { # <screen file> -> prints "cur max" or nothing
    grep -oE 'Mana:[0-9]+/[0-9]+' "$1" | head -1 | sed -e 's/Mana://' -e 's#/# #'
}

read -r ARRIVAL_CUR ARRIVAL_MAX <<<"$(_mana_of "$ARRIVAL_FILE")"
read -r CASTS_CUR CASTS_MAX <<<"$(_mana_of "$CASTS_FILE")"
read -r WAIT_CUR WAIT_MAX <<<"$(_mana_of "$WAIT_FILE")"

for v in ARRIVAL_CUR ARRIVAL_MAX CASTS_CUR CASTS_MAX WAIT_CUR WAIT_MAX; do
    [ -n "${!v}" ] || _check_die 2 \
        "could not read $v off its screen dump. Grep found no 'Mana:cur/max'" \
        "on one of arrival, after-casts or after-wait."
done

# The authoritative save dump, for the held-mana confirmation the screen
# never shows. The key script ends with a normal Save and Continue, so the
# session owns a save under $CHECK_RUN/save/ named for the character, not
# for the fixture file it was loaded from (that name is kept as .backup).
SAVE="$(ls "$CHECK_RUN"/save/*.sav 2>/dev/null | grep -v '\.backup$' | head -1)"
[ -n "$SAVE" ] || _check_die 2 \
    "no saved .sav under $CHECK_RUN/save (excluding the loaded fixture's" \
    ".backup copy). Did the key script's Save and Continue run?"

DUMP="$(tools/dump_save.sh "$SAVE" 2>&1)" || _check_die 2 \
    "tools/dump_save.sh failed on the session's own save:" "$DUMP"

DUMP_LINE="$(printf '%s\n' "$DUMP" | grep '^Mana:')"
[ -n "$DUMP_LINE" ] || _check_die 2 \
    "tools/dump_save.sh printed no Mana: line. Full output:" "$DUMP"

DUMP_CUR="$(echo "$DUMP_LINE" | grep -oE '^Mana: *[0-9]+' | grep -oE '[0-9]+')"
DUMP_MAX="$(echo "$DUMP_LINE" | grep -oE '/ *[0-9]+' | grep -oE '[0-9]+')"
DUMP_HELD="$(echo "$DUMP_LINE" | grep -oE 'held [0-9]+' | grep -oE '[0-9]+')"

[ -n "$DUMP_CUR" ] && [ -n "$DUMP_MAX" ] && [ -n "$DUMP_HELD" ] || _check_die 2 \
    "could not parse the save dump's Mana line: $DUMP_LINE"

FAIL=0

if [ "$CASTS_CUR" -ge "$ARRIVAL_CUR" ]; then
    echo "FAIL: mana after the casts ($CASTS_CUR) is not lower than the"
    echo "      starting mana ($ARRIVAL_CUR). No spell was actually cast."
    FAIL=1
fi

CASTS_PCT=$((CASTS_CUR * 100 / CASTS_MAX))
if [ "$CASTS_PCT" -lt 35 ] || [ "$CASTS_PCT" -gt 80 ]; then
    echo "FAIL: mana after the casts ($CASTS_CUR/$CASTS_MAX = $CASTS_PCT%) is"
    echo "      not inside the 35-80% band this fix cares about."
    FAIL=1
fi

if [ "$WAIT_CUR" -ne "$CASTS_CUR" ]; then
    echo "FAIL: mana after the wait ($WAIT_CUR) does not equal mana after the"
    echo "      casts ($CASTS_CUR). Waiting without resting must not change"
    echo "      mana on the fixed formula; a rise is the un-fixed floor."
    FAIL=1
fi

if [ "$DUMP_CUR" -ne "$WAIT_CUR" ]; then
    echo "FAIL: the save dump's mana ($DUMP_CUR) does not match the screen's"
    echo "      after-wait reading ($WAIT_CUR). A save must not change mana."
    FAIL=1
fi

if [ "$DUMP_HELD" -ne 0 ]; then
    echo "FAIL: held mana is $DUMP_HELD, not 0. Burning Hands should never"
    echo "      touch it; the percentage math above assumed it was zero."
    FAIL=1
fi

echo
echo "--- what was read ---"
echo "  arrival:     $ARRIVAL_CUR/$ARRIVAL_MAX"
echo "  after casts: $CASTS_CUR/$CASTS_MAX ($CASTS_PCT%)"
echo "  after wait:  $WAIT_CUR/$WAIT_MAX"
echo "  save dump:   $DUMP_LINE"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

echo
echo "PASS: seed $SEED -- 35 casts of Burning Hands took mana from"
echo "      $ARRIVAL_CUR/$ARRIVAL_MAX to $CASTS_CUR/$CASTS_MAX ($CASTS_PCT%,"
echo "      inside 35-80%), and about 75 turns of searching without resting"
echo "      left it unchanged at $WAIT_CUR/$WAIT_MAX, held mana 0."
exit 0
