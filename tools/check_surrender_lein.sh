#!/bin/bash
# gate: live
# Surrender must print the hobgoblin's 750 gold lein (inc-ur9b).
# The sentence itself must be present before its amount can be judged.
# Usage: tools/check_surrender_lein.sh (0 pass, 1 fail, 2 cannot measure)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_OPTIONS="$CHECK_OPTIONS"
export INCURSION_LOAD=tools/fixtures/chars/kobold-rogue-seed1.sav
mkdir -p "$CHECK_ROOT/logs/runs" || _check_die 2 "cannot create runs directory"
INCURSION_RUN_DIR="$(mktemp -d "$CHECK_ROOT/logs/runs/surrender-lein.XXXXXX")" ||
    _check_die 2 "cannot create a private run directory"
export INCURSION_RUN_DIR

check_run tools/keys/surrender-lein-message.keys 2
compgen -G "$CHECK_RUN/logs/screens/*-lein-message.txt" >/dev/null ||
    _check_die 1 "surrender sentence missing: the lein screen was never reached"
check_screens '*-lein-message'
check_expect "gold from you as a lein" "the surrender sentence was reached" ||
    _check_die 1 "surrender sentence missing: never reached the lein message"
check_expect "claims 750 gold" "the hobgoblin claims the correct amount" ||
    _check_die 1 "wrong lein amount: reached the sentence, but expected claims 750 gold"
check_done "surrender prints the hobgoblin's 750 gold lein"
