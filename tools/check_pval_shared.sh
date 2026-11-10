#!/bin/bash
# gate: live
# inc-q4kjl: a script's SetPVal must not write the shared effect resource.
#
# WHAT IS BEING GUARDED. SetPVal (src/VMachine.cpp) is how an effect's
# EV_CALC_EFFECT handler sets the power value of the cast in progress. Every
# cast site points e.EMagic at the module's shared effect resource, so the old
# in-place write changed the spell for every later reader, and a save, which
# does not carry module data, reloaded the original value. Now SetPVal copies
# the component into the event (EventInfo::EMagicCopy) first.
#
# THE ORACLE is the PVAL_PROBE line INCURSION_PVAL_PROBE=<path> makes SetPVal
# append: the effect name, the values written, and the SHARED resource's pval
# right after the write. Each Mage Armour line becomes a one-line synthetic
# screen (as tools/check_cast_rules.sh does), and the assertions read those.
# Pass: Mage Armour has at least one line, the cast really happened ("You feel
# safe."), and no line shows the shared pval equal to the value just written.
# Mage Armour's own pval is a level-scaled 15d1, so it can never equal the
# written 0d0+N.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation
# removes the copy in SetPVal, which brings back the in-place write.
#
# fact: character -- fixture human-priest-mage-seed4-gate
# fact: settings -- tools/fixtures/options-2026-08-22.dat
# fact: hostile creature beside the player -- wizard "Genocide Everything"
# fact: ring mail worn, which cancels the spell -- inventory take-off in the keys
# fact: spell success roll -- wizard switch "Ignore Spell Failure"
# fact: the written value (Luck modifier) -- never asserted, only compared to the shared pval
#
# Usage: tools/check_pval_shared.sh [--prove-red]
#   0 every expectation holds   1 one fails   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/human-priest-mage-seed4-gate.sav
KEYS=tools/keys/pval-shared-cast.keys
SEED=4

check_mutation src/VMachine.cpp \
'      if (e.EMagic != &e.EMagicCopy) {
        e.EMagicCopy = *e.EMagic;
        e.EMagic = &e.EMagicCopy;
        }' \
'      if (e.EMagic != &e.EMagicCopy) {
        }'

[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE to load."
[ -f "$KEYS" ]    || _check_die 2 "no $KEYS to run."

mkdir -p logs
PROBE="$PWD/logs/pval-probe-$$.txt"
rm -f "$PROBE"
trap 'rm -f "$PROBE"' EXIT
export INCURSION_LOAD="$FIXTURE"
export INCURSION_PVAL_PROBE="$PROBE"

check_run "$KEYS" "$SEED"
RUN="$CHECK_RUN"
[ -f "$PROBE" ] && cp "$PROBE" "$RUN/logs/pval-probe.txt"

# One synthetic screen per Mage Armour probe line. An absent probe file or no
# Mage Armour line leaves a screen that says so, and the expectation below then
# fails: a check that cannot see the event must not pass.
SCR="$RUN/logs/screens"
n=0
: > "$SCR/probe-none.txt"
if [ -f "$PROBE" ]; then
    while IFS= read -r line; do
        n=$((n + 1))
        wrote="$(printf '%s\n' "$line" | sed -n 's/.* wrote=\([^ ]*\) .*/\1/p')"
        shared="$(printf '%s\n' "$line" | sed -n 's/.* shared=\(.*\)$/\1/p')"
        if [ -z "$wrote" ] || [ -z "$shared" ]; then
            verdict="UNREADABLE probe line: $line"
        elif [ "$wrote" = "$shared" ]; then
            verdict="SHARED RESOURCE OVERWRITTEN: wrote $wrote, shared now $shared"
        else
            verdict="shared resource intact: wrote $wrote, shared stays $shared"
        fi
        printf 'Mage Armour: %s\n' "$verdict" > "$SCR/probe-$n.txt"
    done < <(grep '^PVAL_PROBE effect=Mage Armour ' "$PROBE")
fi
[ "$n" -gt 0 ] && rm -f "$SCR/probe-none.txt"
[ "$n" -eq 0 ] && printf 'no Mage Armour PVAL_PROBE line\n' > "$SCR/probe-none.txt"

check_screens 'probe-*'
check_expect "Mage Armour: shared resource intact" \
    "SetPVal ran for Mage Armour and left the shared resource's pval alone"
check_reject "SHARED RESOURCE OVERWRITTEN" \
    "no Mage Armour SetPVal wrote the shared resource"
check_reject "UNREADABLE probe line" "every probe line was readable"

check_screens '*msgs'
check_expect "You feel safe." "the Mage Armour cast took effect"

check_done "SetPVal leaves the shared effect resource alone ($n Mage Armour probe lines)"
