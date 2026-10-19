#!/bin/bash
# gate: live
# Does a Ranger get Fasting, as the Ranger class help promises? (bd inc-4us6)
#
# THE DEFECT. The help says rangers get hungry at 1/3rd the rate of others, in
# proportion to ranger levels. The Ranger Grants list in lib/classes.irh had no
# Ability[CA_FASTING] line, so no Ranger had Fasting.
#
# THE ORACLE. Two Human seed-1 characters are made by key script: a Ranger and
# a Warrior (the control). INCURSION_CHAR_PROBE writes logs/charprobe.txt, whose
# Special Abilities list must name Fasting for the Ranger only. INCURSION_HUNGER_PROBE
# logs, before it forces anything, the character's own values:
#   HUNGER_PROBE case=live fasting=<n> M=<n>
# The Ranger needs fasting >= 1 and an M strictly below the Warrior's.
#
# PROVED RED with --prove-red: the mutation removes the Ranger Fasting grant.
#
# Usage: tools/check_ranger_fasting.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation lib/classes.irh \
'      Ability[CA_FASTING,+1]            at every level starting at 1st,
' \
''

export INCURSION_CHAR_PROBE=1
export INCURSION_HUNGER_PROBE=1

check_run tools/keys/kit-ranger.keys 1
RANGER_RUN="$CHECK_RUN"
check_run tools/keys/kit-warrior.keys 1
WARRIOR_RUN="$CHECK_RUN"

for f in "$RANGER_RUN/logs/charprobe.txt" "$WARRIOR_RUN/logs/charprobe.txt" \
    "$RANGER_RUN/logs/errors.log" "$WARRIOR_RUN/logs/errors.log"; do
    [ -s "$f" ] || _check_die 2 "expected output is missing or empty: $f"
done

live() { # <run dir> -> the case=live line, backtrace blocks dropped
    grep -v '^    ' "$1/logs/errors.log" | grep 'HUNGER_PROBE case=live ' | head -1
}
R_LINE="$(live "$RANGER_RUN")"
W_LINE="$(live "$WARRIOR_RUN")"
[ -n "$R_LINE" ] && [ -n "$W_LINE" ] || _check_die 2 \
    "the probe never logged HUNGER_PROBE case=live for both characters." \
    "Does this build contain Character::HungerProbe() and the live line?"

num() { echo "$1" | grep -oE "$2=-?[0-9]+" | sed "s/$2=//"; }
R_F="$(num "$R_LINE" fasting)"; R_M="$(num "$R_LINE" M)"
W_F="$(num "$W_LINE" fasting)"; W_M="$(num "$W_LINE" M)"
for v in R_F R_M W_F W_M; do
    [ -n "${!v}" ] || _check_die 2 "could not parse $v from:" "  $R_LINE" "  $W_LINE"
done

# The Special Abilities section runs from its heading to the next blank line.
abil() { awk '/^Special Abilities:/ {on=1; next} on && /^$/ {exit} on' "$1"; }
R_AB="$(abil "$RANGER_RUN/logs/charprobe.txt")"
W_AB="$(abil "$WARRIOR_RUN/logs/charprobe.txt")"
[ -n "$R_AB" ] || _check_die 2 "the Ranger sheet has no Special Abilities section."

FAIL=0
if ! printf '%s\n' "$R_AB" | grep -q 'Fasting'; then
    echo "FAIL: the Ranger's Special Abilities do not list Fasting."
    FAIL=1
fi
if printf '%s\n' "$W_AB" | grep -q 'Fasting'; then
    echo "FAIL: the Warrior's Special Abilities list Fasting; the control is bad."
    FAIL=1
fi
if [ "$R_F" -lt 1 ]; then
    echo "FAIL: the Ranger's live Fasting level is $R_F (wanted >= 1)."
    FAIL=1
fi
if [ "$R_M" -ge "$W_M" ]; then
    echo "FAIL: the Ranger's hunger multiplier M=$R_M is not below the Warrior's M=$W_M."
    FAIL=1
fi

echo
echo "--- what the probes logged ---"
echo "ranger : $R_LINE"
echo "warrior: $W_LINE"
echo "ranger  Special Abilities:"; printf '%s\n' "$R_AB" | sed 's/^/  | /'
echo "warrior Special Abilities:"; printf '%s\n' "$W_AB" | sed 's/^/  | /'

[ "$FAIL" -eq 0 ] || exit 1
echo
echo "PASS: Ranger fasting=$R_F M=$R_M, Warrior fasting=$W_F M=$W_M;"
echo "      the Ranger sheet lists Fasting and the Warrior sheet does not."
exit 0
