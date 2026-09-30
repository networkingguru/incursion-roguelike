#!/bin/bash
# gate: live
# Intensive Study ("Improve Caster Level") must raise spell slots along with
# caster level, because the game's own text says so. RED on current code:
# the slot grant ignores the study. (bd inc-ngku)
#
# THE ORACLE is the game's own words, not the SRD. lib/help.irh:3962 says
# "Caster levels determine ... the number of spell slots characters have which
# they can spend to learn spells", and the worked example at lib/help.irh:4076
# has Lady Sarah buy Intensive Study three times "to increase her caster levels"
# and states the feat "would give her a fourth-level spell slot". src/FeatTab.cpp:507
# (the feat's in-game description) repeats it: "This both increases your caster
# level and gives you access to the higher level spells on the spellcasting
# chart." So the game promises slots, and the reading below is against that
# promise.
#
# THE DEFECT. Player::GainAbility, case CA_SPELLCASTING (src/Create.cpp)
# raises SpellSlots[i] up to SpellTable[Abilities[ab]][i] -- the RAW ability.
# Intensive Study raises the EFFECTIVE level instead, via
# IntStudy[STUDY_CASTING] inside Creature::AbilityLevel (src/Creature.cpp:3086),
# and no slot code reads that, so the slots never follow the caster level.
#
# THE READING. INCURSION_STUDY_PROBE arms Character::StudySlotsProbe()
# (src/Create.cpp), run once at the top of Game::Play() on the live loaded
# player (src/Main.cpp). It applies the study exactly as the level-up case does
# (IntStudy[choice]++ in Player::GainFeat, src/Create.cpp) and logs one line:
#   STUDY_PROBE raw=<n> eff=<n> slots=<9 comma numbers> rawchart=<...> effchart=<...>
# where slots is the live SpellSlots[] after the study, rawchart is
# SpellTable[raw] and effchart is SpellTable[eff] (the level the study just
# raised). The character is a frozen Bard caster fixture, so raw and eff differ
# by exactly the one study step.
#
# THE PROPERTY. slots must equal effchart. On current code slots equal rawchart
# instead, so this check exits 1 (red). Grant the slots from the effective level
# and it exits 0.
#
# It MUST fail (exit 1), never pass or read as inconclusive, when the probe line
# cannot be found: a check whose oracle silently says nothing is worse than none.
#
# Usage: tools/check_study_slots.sh   (0 pass, 1 fail, 2 could not measure)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

SEED=1
KEYS=tools/keys/load-char-sheet.keys
# A frozen single-class caster: Bard 7, caster level 3 on the chart, so the
# study step takes it to 4 and the two charts differ in a way a check can see.
# Known-good under the 2026-08-22 settings. See tools/fixtures/README.md.
LOAD=tools/fixtures/chars/prestige-geomancy-seed1-opt0822.sav

export INCURSION_STUDY_PROBE=1
export INCURSION_LOAD="$LOAD"

check_run "$KEYS" "$SEED"

LOG="$CHECK_RUN/logs/errors.log"

# No log, no line: the probe never ran. This is a FAIL and not an
# inconclusive, per the header: the check must not pass on a silent oracle.
if [ ! -s "$LOG" ]; then
    echo "FAIL: the run logged nothing at all. The probe reports through"
    echo "      Error(), so an empty log means it never ran. Is"
    echo "      Character::StudySlotsProbe() still called from Game::Play()"
    echo "      (src/Main.cpp), and does this build contain it?"
    echo "      run: $CHECK_RUN"
    exit 1
fi

# Drop the indented backtrace blocks headless.sh attaches after a message's
# first occurrence; they quote the message text and would be counted twice.
CLEAN="$(grep -v '^    ' "$LOG")"
LINE="$(printf '%s\n' "$CLEAN" | grep 'STUDY_PROBE raw=' | head -1)"

if [ -z "$LINE" ]; then
    echo "FAIL: the log holds no STUDY_PROBE line, so the independent reading"
    echo "      the check is built on is absent. run: $CHECK_RUN"
    exit 1
fi

RAW="$(echo "$LINE" | grep -oE 'raw=-?[0-9]+' | sed 's/raw=//')"
EFF="$(echo "$LINE" | grep -oE 'eff=-?[0-9]+' | sed 's/eff=//')"
SLOTS="$(echo "$LINE" | sed -n 's/.* slots=\([0-9,]*\).*/\1/p')"
EFFCHART="$(echo "$LINE" | sed -n 's/.* effchart=\([0-9,]*\).*/\1/p')"
RAWCHART="$(echo "$LINE" | sed -n 's/.* rawchart=\([0-9,]*\).*/\1/p')"

for pair in "RAW:$RAW" "EFF:$EFF" "SLOTS:$SLOTS" "EFFCHART:$EFFCHART" \
            "RAWCHART:$RAWCHART"; do
    name="${pair%%:*}"; val="${pair#*:}"
    [ -n "$val" ] || { echo "FAIL: could not parse $name out of: $LINE"; exit 1; }
done

echo
echo "--- what the probe logged ---"
echo "$LINE"
echo
echo "raw ability level : $RAW"
echo "effective level   : $EFF   (raw + intensive study)"
echo "live slots        : $SLOTS"
echo "chart at raw      : $RAWCHART"
echo "chart at effective: $EFFCHART"
echo

# The study must actually have moved the caster level, or there is nothing to
# test: a fixture whose raw and effective levels were equal would make the
# property true for the wrong reason.
if [ "$EFF" -le "$RAW" ]; then
    echo "FAIL: the study did not raise the caster level (raw=$RAW eff=$EFF),"
    echo "      so this run cannot say anything about slots. The fixture or the"
    echo "      probe changed. run: $CHECK_RUN"
    exit 1
fi

# THE ASSERTION, level by level, so a partial grant is caught too.
IFS=',' read -r -a slotv <<< "$SLOTS"
IFS=',' read -r -a effv <<< "$EFFCHART"
IFS=',' read -r -a rawv <<< "$RAWCHART"

FAIL=0
for i in 0 1 2 3 4 5 6 7 8; do
    lvl=$((i + 1))
    if [ "${slotv[$i]}" -ne "${effv[$i]}" ]; then
        echo "FAIL: level $lvl slots = ${slotv[$i]}, but the chart at the"
        echo "      study-raised caster level $EFF has ${effv[$i]}"
        echo "      (the chart at the raw level $RAW has ${rawv[$i]})."
        echo "      Intensive Study raised the caster level and the slot that"
        echo "      follows it was not granted. inc-ngku."
        FAIL=1
    fi
done

if [ "$FAIL" -ne 0 ]; then
    echo
    echo "FAIL: after Intensive Study the spell slots do not match the chart at"
    echo "      the caster level the study produced. See $CHECK_RUN"
    exit 1
fi

echo "PASS: with caster level raised from $RAW to $EFF by Intensive Study,"
echo "      SpellSlots equals the chart at the effective level ($EFFCHART)."
echo "      ($CHECK_RUN/logs/errors.log)"
exit 0
