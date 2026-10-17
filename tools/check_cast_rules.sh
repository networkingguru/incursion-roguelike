#!/bin/bash
# gate: live
# inc-4999 phase 4b: the version the player cast decides every rule.
#
# WHAT IS BEING GUARDED. Player::Spells[sp] keeps a kind bit per source a spell
# is HELD from, but a cast is of ONE version (a spell number plus a source). The
# rule readers -- Creature::SpellRating, Creature::getSpellDC and
# Creature::getSpellMana -- now read Character::SpellCastFlags(sp, src), which
# keeps only the cast version's own kind bit, not every held one. So a spell
# held arcane AND divine no longer gets "best of both": the arcane cast uses
# INT and the arcane armor penalty and needs no focus; the divine cast uses WIS
# and needs a holy symbol and the god's approval.
#
# THE CHARACTER is tools/fixtures/chars/human-priest-mage-dual-seed4-gate.sav:
# Kethad, Priest 1 / Mage 1, holding Protection from Evil from BOTH sources. He
# wears ring mail +3 (body armour) at the Armour slot and a Holy symbol of
# Aiswin at the Neck slot, so the key scripts can take either off through the
# inventory menu (i, the slot letter, SPACE, ESC).
#
# THE ORACLE is the CAST_RULES probe line INCURSION_CAST_PROBE writes from
# Creature::Cast once the cast's success chance, save DC attribute and focus are
# known: CAST_RULES spell=<n> source=<..> chance=<n> raw=<n> dcattr=<Int|Wis|Cha>
# focus=<book|symbol|none>. The divine cast that fails the focus test is refused
# before the probe, so it leaves only a CAST_PROBE line plus the game's own
# message, which is the other half of case (a).
#
# HOW EVERY CASE ASSERTS. This check reads through tools/check_lib.sh, whose
# check_done counts the assertions check_expect and check_reject make -- a check
# that only prints its own "ok" lines is reported INCONCLUSIVE, because its pass
# cannot be told from a run that measured nothing. check_expect reads screen
# dumps, so each probe-derived value is written as a one-line synthetic screen
# under the run (probe-*.txt), and that screen is the one asserted on: the line
# carries the value the run produced, and the assertion is the value wanted, so
# the two differ exactly when the rule reader is wrong.
#
#   a. symbol off. The arcane cast passes the focus test -- its CAST_RULES line
#      carries focus=none -- and the divine cast is refused with "You need
#      to have a holy symbol equipped to cast divine spells."
#   b. symbol on. Both casts pass; dcattr=Int for arcane and Wis for divine.
#   c. armour on vs off. The arcane raw chance is LOWER with the ring mail than
#      without it (raw reads the pre-cap sum, which the capped chance hides --
#      Protection from Evil happens to sit at the 100 cap either way); the
#      divine raw chance is the same with and without armour.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation makes
# Character::SpellCastFlags keep every held kind bit (best of both again). The
# divine cast of Protection from Evil then sees SP_ARCANE and needs no symbol,
# so case (a)'s refusal message never appears and the check exits 1.
#
# Usage: tools/check_cast_rules.sh [--prove-red]
#   0 every expectation holds   1 one fails   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/human-priest-mage-dual-seed4-gate.sav
KEYS_NOSYM=tools/keys/cast-rules-nosym.keys
KEYS_SYM=tools/keys/cast-rules-sym.keys
KEYS_NOARMOR=tools/keys/cast-rules-noarmor.keys
SEED=4

check_mutation src/Magic.cpp \
'    for (i = 0; i != 4; i++)
      flags &= ~kinds[i];' \
'    for (i = 0; i != 4; i++)
      flags |= 0;'

[ -f "$FIXTURE" ]      || _check_die 2 "no $FIXTURE to load."
[ -f "$KEYS_NOSYM" ]   || _check_die 2 "no $KEYS_NOSYM to run."
[ -f "$KEYS_SYM" ]     || _check_die 2 "no $KEYS_SYM to run."
[ -f "$KEYS_NOARMOR" ] || _check_die 2 "no $KEYS_NOARMOR to run."

export INCURSION_LOAD="$FIXTURE"
export INCURSION_CAST_PROBE=1

# rules_line <log> <source> -- the CAST_RULES line for that source. Empty when
# there is no such line (the divine cast that fails the focus test is refused
# before the probe, so it leaves none).
rules_line() { # <log> <source>
    grep -E "^[0-9].*CAST_RULES spell=Protection_from_Evil source=$2 " "$1" | head -1
}

# rules_field <log> <source> <field> -- the value of <field> on the CAST_RULES
# line for that source. Empty when there is no such line.
rules_field() { # <log> <source> <chance|raw|dcattr|focus>
    local line
    line="$(rules_line "$1" "$2")"
    [ -n "$line" ] || return 0
    printf '%s\n' "$line" | sed -n "s/.* $3=\([^ ]*\).*/\1/p"
}

# probe_screen <run> <name> <text> -- write a one-line synthetic screen into the
# run, holding the value the probe produced, and choose it. The assertions below
# then read it with check_expect like any other screen dump, so a value that is
# wrong makes the chosen screen carry the wrong text and the assertion fail.
probe_screen() { # <run> <name> <text>
    local run="$1" name="$2" text="$3"
    printf '%s\n' "$text" > "$run/logs/screens/probe-$name.txt"
    check_screens "probe-$name"
}

# ---------------------------------------------------------------- case (a)
# symbol off: arcane passes the focus test, divine is refused.
check_run "$KEYS_NOSYM" "$SEED"
RUN_NOSYM="$CHECK_RUN"
LOG="$RUN_NOSYM/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 "the no-symbol run logged nothing; see $RUN_NOSYM"

a_arc="$(rules_line "$LOG" arcane)"
[ -n "$a_arc" ] || _check_die 2 "no arcane CAST_RULES line; see $LOG"
probe_screen "$RUN_NOSYM" a-arcane "$a_arc"
check_expect "source=arcane" "a: the arcane cast produced a CAST_RULES line"
check_expect "focus=none"    "a: the arcane cast passes the focus test (focus=none)"

check_screens '*'
check_expect "You need to have a holy symbol equipped to cast divine spells." \
    "a: the divine cast is refused for want of a holy symbol"

# ---------------------------------------------------------------- case (b)
# symbol on: both pass; the arcane DC uses INT and the divine DC uses WIS.
check_run "$KEYS_SYM" "$SEED"
RUN_SYM="$CHECK_RUN"
LOG="$RUN_SYM/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 "the with-symbol run logged nothing; see $RUN_SYM"

b_arc="$(rules_line "$LOG" arcane)"
b_div="$(rules_line "$LOG" divine)"
[ -n "$b_arc" ] || _check_die 2 "no arcane CAST_RULES line; see $LOG"
[ -n "$b_div" ] || _check_die 2 "no divine CAST_RULES line; see $LOG"

probe_screen "$RUN_SYM" b-arcane "$b_arc"
check_expect "focus=none" "b: arcane cast needs no focus"
check_expect "dcattr=Int" "b: arcane save DC uses Int"

probe_screen "$RUN_SYM" b-divine "$b_div"
check_expect "focus=symbol" "b: divine cast needs a holy symbol"
check_expect "dcattr=Wis"   "b: divine save DC uses Wis"

# ---------------------------------------------------------------- case (c)
# armour on (RUN_SYM) vs off.
check_run "$KEYS_NOARMOR" "$SEED"
RUN_NOARMOR="$CHECK_RUN"
LOG="$RUN_NOARMOR/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 "the no-armour run logged nothing; see $RUN_NOARMOR"

c_sym_arc="$(rules_field "$RUN_SYM/logs/errors.log" arcane raw)"
c_sym_div="$(rules_field "$RUN_SYM/logs/errors.log" divine raw)"
c_nam_arc="$(rules_field "$LOG" arcane raw)"
c_nam_div="$(rules_field "$LOG" divine raw)"

if [ -z "$c_sym_arc" ] || [ -z "$c_nam_arc" ] || [ -z "$c_sym_div" ] || [ -z "$c_nam_div" ]; then
    _check_die 2 "case (c) needs four CAST_RULES raw numbers; got" \
        "armour arcane='$c_sym_arc' divine='$c_sym_div'" \
        "no-armour arcane='$c_nam_arc' divine='$c_nam_div'"
fi

if [ "$c_sym_arc" -lt "$c_nam_arc" ]; then
    c_arc_verdict="arcane-raw-lower-in-armour yes ($c_sym_arc < $c_nam_arc)"
else
    c_arc_verdict="arcane-raw-lower-in-armour no ($c_sym_arc vs $c_nam_arc)"
fi
probe_screen "$RUN_NOARMOR" c-arcane "$c_arc_verdict"
check_expect "arcane-raw-lower-in-armour yes" \
    "c: arcane raw chance is lower in armour ($c_sym_arc < $c_nam_arc)"

if [ "$c_sym_div" -eq "$c_nam_div" ]; then
    c_div_verdict="divine-raw-unchanged-by-armour yes ($c_sym_div = $c_nam_div)"
else
    c_div_verdict="divine-raw-unchanged-by-armour no ($c_sym_div vs $c_nam_div)"
fi
probe_screen "$RUN_NOARMOR" c-divine "$c_div_verdict"
check_expect "divine-raw-unchanged-by-armour yes" \
    "c: divine raw chance is unchanged by armour ($c_sym_div = $c_nam_div)"

echo
echo "runs: no-symbol=$RUN_NOSYM  with-symbol=$RUN_SYM  no-armour=$RUN_NOARMOR"
check_done "the version cast decides the focus, the save-DC attribute and the armour penalty"
