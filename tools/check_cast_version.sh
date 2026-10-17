#!/bin/bash
# gate: live
# inc-4999 phase 4a: does the cast menu list each HELD VERSION of a spell
# separately, and does the version the player picks reach Creature::Cast as its
# own source?
#
# WHAT IS BEING GUARDED. Player::Spells[sp] keeps, per spell, a kind bit per
# source it is HELD from (SP_ARCANE, SP_DIVINE, SP_PRIMAL, SP_BARDIC). A
# Priest/Mage can hold one spell from two sources. TextTerm::SpellManager
# (src/Managers.cpp) now builds one menu entry per held version, packs
# (spell number, source) into an int16 "version" and returns that; the cast
# path unpacks the spell number for the engine and sets EventInfo.SpellSource
# (inc/Events.h) from the version's source. The rule readers that act on it are
# phase 4b; this check only proves the choice is carried.
#
# THE CHARACTER is tools/fixtures/chars/human-priest-mage-dual-seed4-gate.sav:
# Kethad, Priest 1 / Mage 1, holding Protection from Evil from BOTH sources
# (arcane=1 divine=1), saved in wizard mode at depth 2. Protection from Evil has
# qval 0, so a cast prompts for no target.
#
# THE ORACLES:
#   A (screen). tools/keys/cast-version-dual.keys opens the cast menu ('m'). The
#     menu must show TWO Protection from Evil rows, tagged "(arc)" and "(div)"
#     (phase 5: the tag leads every row). A run with no dump exits 2.
#   B (probe). INCURSION_CAST_PROBE=1 makes Creature::Cast write one errors.log
#     line at entry per player cast: CAST_PROBE spell=<name> source=<...>. The
#     script casts the arcane row then the divine row of Protection from Evil.
#     The log must carry source=arcane AND source=divine for
#     Protection_from_Evil, which is the version reaching the cast intact.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation makes
# Player::CastSourceFor (src/Magic.cpp) ignore the version's own source code and
# always answer with the first held source (arcane). The menu and both casts
# still happen, so the run reaches the assertions; the second probe line then
# reads source=arcane instead of source=divine and the check exits 1.
#
# Usage: tools/check_cast_version.sh [--prove-red]
#   0 every expectation holds   1 one fails   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/human-priest-mage-dual-seed4-gate.sav
KEYS=tools/keys/cast-version-dual.keys
SEED=4

check_mutation src/Magic.cpp \
'    srcCode = SpellVersionSrcCode(version);
    if (srcCode != SP_SRC_NONE)
      return SpellSrcCodeKind(srcCode);' \
'    srcCode = SpellVersionSrcCode(version);
    if (srcCode != SP_SRC_NONE && 0)
      return SpellSrcCodeKind(srcCode);'

[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE to load."
[ -f "$KEYS" ]    || _check_die 2 "no $KEYS to run."

export INCURSION_LOAD="$FIXTURE"
export INCURSION_CAST_PROBE=1
check_run "$KEYS" "$SEED"

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 "the run logged nothing, so no cast was proved."

# A. the menu lists the two held versions of one spell, told apart by tag.
check_screens '*-cast-menu'
check_expect "(arc)Protection from" "A: the arcane version is a menu row of its own"
check_expect "(div)Protection from" "A: the divine version is a menu row of its own"

# B. each chosen version reaches Creature::Cast with its own source.
FAIL=0
probe_line() { # <source> -- the first CAST_PROBE line for Protection_from_Evil
    grep -E "^[0-9].*CAST_PROBE spell=Protection_from_Evil source=$1\$" "$LOG" |
        head -1
}
for src in arcane divine; do
    if [ -n "$(probe_line "$src")" ]; then
        echo "  ok    CAST_PROBE names source=$src for Protection_from_Evil"
    else
        echo "  FAIL  no CAST_PROBE line with source=$src for Protection_from_Evil"
        FAIL=1
    fi
done

if [ "$(grep -cE '^[0-9].*CAST_PROBE spell=Protection_from_Evil ' "$LOG")" -lt 2 ]; then
    _check_die 2 "fewer than two CAST_PROBE lines for Protection_from_Evil, so" \
        "the script did not drive both casts. See $LOG."
fi

if [ "$FAIL" -ne 0 ]; then
    echo
    echo "FAIL: the version the player chose did not reach the cast as its own"
    echo "      source (inc-4999 phase 4a)."
    exit 1
fi

check_done "the cast menu lists each held version and each chosen version reaches the cast"
