#!/bin/bash
# gate: live
# Guards the per-turn hunger clock of inc-i9q.2: a player loses 1 point of
# nutrition per 1008 ticks, scaled by Burning Hunger multipliers (capped at
# 7), by speed measured as half its distance from 100% (M=125 at +10 speed,
# M=90 at -4, M=150 at +20), doubled while regenerating, and reduced while
# Fasting; reaching 0 starves the character to death.
#
# THE ORACLE is the pair of probes below. INCURSION_HUNGER_PROBE arms
# Character::HungerProbe() (src/Create.cpp), which runs on the live loaded
# player and drives real Creature::DoTurn() ticks, narrating through Error():
#   HUNGER_PROBE case=base before=<n> after=<n> drop=<n>
#   HUNGER_PROBE case=M name=<name> M=<n>
#   HUNGER_PROBE case=fasting before=<n> after=<n> drop=<n>
#   HUNGER_PROBE case=rest name=<base|slowmet|reverie|hours8> pts=<n>
# INCURSION_HUNGER_DEATH_PROBE arms the starvation path, logging:
#   HUNGER_PROBE death before has=<0|1>
#   HUNGER_PROBE death after has=<0|1> dead=<0|1>
#
# PROVED RED with --prove-red: the mutation below restores the base code that
# skipped the healing-cost hunger drain.
#
# Usage: tools/check_hunger_clock.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat

SEED=4
KEYS=tools/keys/load-char-sheet.keys

# The mutation this check defends: the base code ran the healing hunger cost
# without the HUNGER-status guard. Declared before the run below so
# --prove-red intercepts here, before the (build-needing) measurement runs.
check_mutation src/Creature.cpp \
'        GetHungrier(hungerHealed);' \
'        ;'

# inc-i9q.2 phase 2: and the rest/SpendHours cost. Only the FIRST mutation is
# proved by --prove-red; this one is still count-guarded on every ordinary run.
check_mutation src/Creature.cpp \
'      return (int32)((long long)ticks * M * 15 / (1008LL * 100 * 35));' \
'      return (int32)((long long)ticks * M / (1008LL * 100));'

export INCURSION_HUNGER_PROBE=1
export INCURSION_HUNGER_DEATH_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav

check_run "$KEYS" "$SEED"

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 \
    "the run logged nothing at all. The probe reports through Error()," \
    "so an empty log means it never ran."

# Drop the indented backtrace blocks headless.sh attaches to a first
# occurrence; they quote the message text and would be counted twice.
CLEAN="$(grep -v '^    ' "$LOG")"

BASE_LINE="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=base ' | head -1)"
FASTING_LINE="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=fasting ' | head -1)"
SLOWMET_LINE="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=slowmet ' | head -1)"
DEATH_LINE="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE death after ' | head -1)"

REST_BASE_LINE="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=rest name=base ' | head -1)"
REST_SLOW_LINE="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=rest name=slowmet ' | head -1)"
REST_REV_LINE="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=rest name=reverie ' | head -1)"
REST_HOURS_LINE="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=rest name=hours8 ' | head -1)"

[ -n "$BASE_LINE" ] && [ -n "$FASTING_LINE" ] && [ -n "$SLOWMET_LINE" ] && \
    [ -n "$DEATH_LINE" ] && \
    [ -n "$REST_BASE_LINE" ] && [ -n "$REST_SLOW_LINE" ] && \
    [ -n "$REST_REV_LINE" ] && [ -n "$REST_HOURS_LINE" ] || _check_die 2 \
    "the probe never logged the base, fasting, slowmet, rest and death lines." \
    "Is Character::HungerProbe() still called from Game::Play() (src/Main.cpp)," \
    "and does this build contain it?"

BASE_BEFORE="$(echo "$BASE_LINE" | grep -oE 'before=-?[0-9]+' | sed 's/before=//')"
BASE_AFTER="$(echo "$BASE_LINE" | grep -oE 'after=-?[0-9]+' | sed 's/after=//')"
BASE_DROP="$(echo "$BASE_LINE" | grep -oE 'drop=-?[0-9]+' | sed 's/drop=//')"
BASE_SPD="$(echo "$BASE_LINE" | grep -oE 'spd=-?[0-9]+' | sed 's/spd=//')"
BASE_M="$(echo "$BASE_LINE" | grep -oE 'M=-?[0-9]+' | sed 's/M=//')"
BASE_CALLS="$(echo "$BASE_LINE" | grep -oE 'calls=[0-9]+' | sed 's/calls=//')"

for v in BASE_SPD BASE_M BASE_CALLS; do
    [ -n "${!v}" ] || _check_die 2 \
        "could not parse $v (spd/M/calls) out of the base probe line:" \
        "  $BASE_LINE"
done

FASTING_BEFORE="$(echo "$FASTING_LINE" | grep -oE 'before=-?[0-9]+' | sed 's/before=//')"
FASTING_AFTER="$(echo "$FASTING_LINE" | grep -oE 'after=-?[0-9]+' | sed 's/after=//')"
FASTING_DROP="$(echo "$FASTING_LINE" | grep -oE 'drop=-?[0-9]+' | sed 's/drop=//')"

SLOWMET_BEFORE="$(echo "$SLOWMET_LINE" | grep -oE 'before=-?[0-9]+' | sed 's/before=//')"
SLOWMET_AFTER="$(echo "$SLOWMET_LINE" | grep -oE 'after=-?[0-9]+' | sed 's/after=//')"
SLOWMET_DROP="$(echo "$SLOWMET_LINE" | grep -oE 'drop=-?[0-9]+' | sed 's/drop=//')"

for v in BASE_BEFORE BASE_AFTER BASE_DROP FASTING_BEFORE FASTING_AFTER FASTING_DROP \
    SLOWMET_BEFORE SLOWMET_AFTER SLOWMET_DROP; do
    [ -n "${!v}" ] || _check_die 2 \
        "could not parse $v out of the probe lines:" \
        "  $BASE_LINE" "  $FASTING_LINE" "  $SLOWMET_LINE"
done

M_base="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=base ' | head -1 | grep -oE 'M=[0-9]+' | sed 's/M=//')"
M_rank3="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=rank3 ' | head -1 | grep -oE 'M=[0-9]+' | sed 's/M=//')"
M_rank9="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=rank9 ' | head -1 | grep -oE 'M=[0-9]+' | sed 's/M=//')"
M_spd10="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=spd+10 ' | head -1 | grep -oE 'M=[0-9]+' | sed 's/M=//')"
M_spdm4="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=spd-4 ' | head -1 | grep -oE 'M=[0-9]+' | sed 's/M=//')"
M_spd20="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=spd+20 ' | head -1 | grep -oE 'M=[0-9]+' | sed 's/M=//')"
M_healing="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=healing ' | head -1 | grep -oE 'M=[0-9]+' | sed 's/M=//')"
M_fasting="$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=fasting ' | head -1 | grep -oE 'M=[0-9]+' | sed 's/M=//')"

for v in M_base M_rank3 M_rank9 M_spd10 M_spdm4 M_spd20 M_healing M_fasting; do
    [ -n "${!v}" ] || _check_die 2 \
        "could not parse $v out of the M probe lines:" \
        "  $CLEAN"
done

REST_base="$(echo "$REST_BASE_LINE" | grep -oE 'pts=-?[0-9]+' | sed 's/pts=//')"
REST_slowmet="$(echo "$REST_SLOW_LINE" | grep -oE 'pts=-?[0-9]+' | sed 's/pts=//')"
REST_reverie="$(echo "$REST_REV_LINE" | grep -oE 'pts=-?[0-9]+' | sed 's/pts=//')"
REST_hours8="$(echo "$REST_HOURS_LINE" | grep -oE 'pts=-?[0-9]+' | sed 's/pts=//')"

for v in REST_base REST_slowmet REST_reverie REST_hours8; do
    [ -n "${!v}" ] || _check_die 2 \
        "could not parse $v out of the rest probe lines:" \
        "  $REST_BASE_LINE" "  $REST_SLOW_LINE" "  $REST_REV_LINE" "  $REST_HOURS_LINE"
done

FAIL=0

if [ "$BASE_CALLS" -ne 17000 ]; then
    echo "FAIL: the base probe ran GetHungrier $BASE_CALLS times, not 17000."
    echo "      the live path did not drive exactly one drain per DoTurn."
    FAIL=1
fi

# inc-i9q.2 phase 4: the expected drop follows the multiplier the probe
# actually measured (17000 updates * 6 hundredths * M / 10000), instead of
# a fixed band. +-150 absorbs the per-update rounding.
BASE_EXPECT=$((17000 * 6 * BASE_M / 10000))
BASE_LO=$((BASE_EXPECT - 150))
BASE_HI=$((BASE_EXPECT + 150))

if [ "$BASE_DROP" -lt "$BASE_LO" ] || [ "$BASE_DROP" -gt "$BASE_HI" ]; then
    echo "FAIL: the base hunger drop per turn is outside the expected band."
    echo "      drop=$BASE_DROP spd=$BASE_SPD M=$BASE_M (wanted $BASE_LO..$BASE_HI" \
         "from 17000*6*$BASE_M/10000=$BASE_EXPECT)"
    FAIL=1
fi

check_m() {
    local name="$1" got="$2" want="$3"
    if [ "$got" -ne "$want" ]; then
        echo "FAIL: multiplier M for $name is wrong."
        echo "      M=$got (wanted $want)"
        FAIL=1
    fi
}

check_m base "$M_base" 100
check_m rank3 "$M_rank3" 300
check_m rank9 "$M_rank9" 700
check_m spd+10 "$M_spd10" 125
check_m spd-4 "$M_spdm4" 90
check_m spd+20 "$M_spd20" 150
check_m healing "$M_healing" 200

if [ "$M_fasting" -ge 100 ]; then
    echo "FAIL: the Fasting multiplier did not reduce hunger."
    echo "      M=$M_fasting (wanted < 100)"
    FAIL=1
fi

if [ "$FASTING_DROP" -le 0 ] || [ "$FASTING_DROP" -ge "$BASE_DROP" ]; then
    echo "FAIL: the Fasting drop is not between 0 and the base drop."
    echo "      fasting drop=$FASTING_DROP base drop=$BASE_DROP (wanted 0 < fasting < base)"
    FAIL=1
fi

if [ "$SLOWMET_DROP" -lt 360 ] || [ "$SLOWMET_DROP" -gt 515 ]; then
    echo "FAIL: the Slow Metabolism drop is outside the expected band."
    echo "      slowmet drop=$SLOWMET_DROP (wanted 360..515 inclusive)"
    FAIL=1
fi

if [ "$SLOWMET_DROP" -ge "$BASE_DROP" ]; then
    echo "FAIL: the Slow Metabolism drop is not below the base drop."
    echo "      slowmet drop=$SLOWMET_DROP base drop=$BASE_DROP (wanted slowmet < base)"
    FAIL=1
fi

check_rest() {
    local name="$1" got="$2" want="$3"
    if [ "$got" -ne "$want" ]; then
        echo "FAIL: the rest hunger cost for $name is wrong."
        echo "      pts=$got (wanted $want)"
        FAIL=1
    fi
}

check_rest base "$REST_base" 142
check_rest slowmet "$REST_slowmet" 61
check_rest reverie "$REST_reverie" 102
check_rest hours8 "$REST_hours8" 61

case "$DEATH_LINE" in
    *has=0\ dead=1*) ;;
    *)
        echo "FAIL: the starvation death line did not report has=0 dead=1."
        echo "      $DEATH_LINE"
        FAIL=1
        ;;
esac

echo
echo "--- what the probe logged ---"
echo "$BASE_LINE"
echo "$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=base ' | head -1)"
echo "$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=rank3 ' | head -1)"
echo "$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=rank9 ' | head -1)"
echo "$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=spd+10 ' | head -1)"
echo "$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=spd-4 ' | head -1)"
echo "$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=spd+20 ' | head -1)"
echo "$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=healing ' | head -1)"
echo "$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE case=M name=fasting ' | head -1)"
echo "$FASTING_LINE"
echo "$SLOWMET_LINE"
echo "$REST_BASE_LINE"
echo "$REST_SLOW_LINE"
echo "$REST_REV_LINE"
echo "$REST_HOURS_LINE"
echo "$(printf '%s\n' "$CLEAN" | grep 'HUNGER_PROBE death before ' | head -1)"
echo "$DEATH_LINE"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

echo
echo "PASS: seed $SEED -- base drop $BASE_DROP per turn (spd=$BASE_SPD M=$BASE_M" \
     "calls=$BASE_CALLS, expected $BASE_EXPECT, in $BASE_LO..$BASE_HI);"
echo "      multipliers base=$M_base rank3=$M_rank3 rank9=$M_rank9"
echo "      spd+10=$M_spd10 spd-4=$M_spdm4 spd+20=$M_spd20 healing=$M_healing"
echo "      fasting M=$M_fasting drop=$FASTING_DROP (< base $BASE_DROP);"
echo "      slowmet drop=$SLOWMET_DROP (< base $BASE_DROP);"
echo "      rest base=$REST_base slowmet=$REST_slowmet reverie=$REST_reverie hours8=$REST_hours8;"
echo "      starvation death reached has=0 dead=1."
exit 0
