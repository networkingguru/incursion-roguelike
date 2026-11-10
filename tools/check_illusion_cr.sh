#!/bin/bash
# gate: live
# inc-q4kjl: an illusory creature's challenge rating follows its spell's script.
#
# WHAT IS BEING GUARDED. Phantasmal Force and its eight sibling illusion spells
# set the power value to max(1, Illusion skill / 2) with SetPVal. Magic::Illusion
# makes the creature at challenge rating e.vDmg (src/Effects.cpp, xe.enCR), and
# e.vDmg comes from the power value that Magic::CalcEffect reads after the
# EV_CALC_EFFECT script. The script used to run in PRE(EV_MAGIC_HIT), after
# e.vDmg was fixed, so the first cast made a CR 0 creature.
#
# THE ORACLE is the ILLUSION_CR line INCURSION_PVAL_PROBE=<path> makes
# Magic::Illusion append: effect, enCR and the caster's Illusion skill. The line
# becomes a one-line synthetic screen (as tools/check_pval_shared.sh does), and
# the assertion wants enCR to equal max(1, skill / 2) for the skill the game
# reports. No line, or CR 0, fails.
#
# PROVED RED by running the check on master's lib/wspells.irh (script in
# PRE(EV_MAGIC_HIT)): see the bead; CHECK_MUTATED style mutation of a .irh is
# not available, so the red run is done by restoring that file and rebuilding.
#
# fact: character -- fixture elf-mage-spotted-seed1 (INCURSION_LOAD)
# fact: settings -- tools/fixtures/options-2026-08-22.dat
# fact: Phantasmal Force is cast through Creature::Cast -- the fixture's spell is not innate
# fact: the cast succeeds -- wizard switch Ignore Spell Failure
# fact: the caster has the mana -- wizard switch Infinite Mana
# fact: monsters stand still and do not act -- wizard switch Freeze Monsters
# fact: the caster's Illusion skill -- read from the probe line, never pinned
#
# Usage: tools/check_illusion_cr.sh
#   0 CR follows the script   1 it does not   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/elf-mage-spotted-seed1.sav
KEYS=tools/keys/illusion-cr-cast.keys
[ -f "$INCURSION_LOAD" ] || _check_die 2 "no $INCURSION_LOAD to load."

mkdir -p logs
PROBE="$PWD/logs/illcr-probe-$$.txt"
rm -f "$PROBE"
trap 'rm -f "$PROBE"' EXIT
export INCURSION_PVAL_PROBE="$PROBE"

check_run "$KEYS" 1
RUN="$CHECK_RUN"
[ -f "$PROBE" ] && cp "$PROBE" "$RUN/logs/pval-probe.txt"

SCR="$RUN/logs/screens"
line=""
[ -f "$PROBE" ] && line="$(grep '^ILLUSION_CR effect=Phantasmal Force ' "$PROBE" | head -1)"
if [ -z "$line" ]; then
    verdict="no ILLUSION_CR line for Phantasmal Force"
else
    cr="$(printf '%s\n' "$line" | sed -n 's/.* enCR=\(-\{0,1\}[0-9]*\) .*/\1/p')"
    sk="$(printf '%s\n' "$line" | sed -n 's/.* skill=\(-\{0,1\}[0-9]*\)$/\1/p')"
    if [ -z "$cr" ] || [ -z "$sk" ]; then
        verdict="UNREADABLE probe line: $line"
    else
        want=$((sk / 2)); [ "$want" -lt 1 ] && want=1
        if [ "$cr" = "$want" ]; then
            verdict="CR follows the script: enCR $cr, Illusion skill $sk"
        else
            verdict="CR WRONG: enCR $cr, but max(1, skill/2) is $want (Illusion skill $sk)"
        fi
    fi
fi
printf 'Phantasmal Force: %s\n' "$verdict" > "$SCR/probe-cr.txt"
check_screens 'probe-cr'
check_expect "CR follows the script" "the illusory creature's CR is max(1, Illusion skill / 2)"
check_reject "CR WRONG" "the CR is not off the script's formula"
check_reject "no ILLUSION_CR line" "the cast reached Magic::Illusion"
check_reject "UNREADABLE" "the probe line was readable"
check_done "illusory creature CR follows the script (${verdict})"
