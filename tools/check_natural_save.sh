#!/bin/bash
# gate: live
# A natural 20 on a saving throw must always succeed, and a natural 1 must
# always fail (SRD 3.5), regardless of Bonus + roll vs DC. (bd inc-e68f)
#
# THE DEFECT. Creature::SavingThrow (src/Creature.cpp) decided success with the
# bare comparison Bonus + roll >= DC, at four sites that must agree: message
# colour, message word, Exercise training gate and return value.
#
# THE ORACLE. The engine prints every save the player can perceive,
# "<name>'s <type> Save: 1d20 (roll) ... = <total> vs DC <n> [success|failure].",
# and OPT_STORE_ROLLS (on in tools/gates/Options.Dat) keeps each one in the
# message log. Two sessions load one frozen paladin and force the die and DC, so
# no seed decides either case (bd inc-b4l3g.11):
#   A (runes)  die forced to 20 (INCURSION_FORCE_SAVE_ROLL), guardian runes DC 27.
#              Bonus + 20 = 23 is below 27, so [success] comes only from the rule.
#   B (tangle) die forced to 1 and DC forced to 1 (INCURSION_FORCE_SAVE_DC).
#              Total 4 is at or above DC 1, so [failure] comes only from the rule.
# A session that prints no matching line is inconclusive (exit 2), never a pass.
#
# fact: character and save bonuses -- fixture human-paladin-seed4-gate, loaded by INCURSION_LOAD
# fact: map and player position -- the fixture save; no run changes depth
# fact: monsters on the level -- wizard switch Freeze Monsters (tools/keys/wizard-switches.keys)
# fact: the d20 roll -- INCURSION_FORCE_SAVE_ROLL (20 in session A, 1 in session B)
# fact: session A DC 27 -- guardian runes data in lib/dungeon.irh, no seed involved
# fact: session B DC -- INCURSION_FORCE_SAVE_DC=1
# fact: text matched -- game strings only; no seed-decided text is asserted
#
# PROVED RED (bd inc-b4l3g.11): removing only `(roll == 20) ? true :` makes
# session A print [failure] and exit 1; removing only `(roll == 1) ? false :`
# makes session B print [success] and exit 1.
#
# Usage: tools/check_natural_save.sh [--prove-red]   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat
FIXTURE=tools/fixtures/chars/human-paladin-seed4-gate.sav
SEED=4

# The mutation this check defends: the special-cased natural 20/1 verdict,
# reverted to upstream's bare comparison.
check_mutation src/Creature.cpp \
'    return (roll == 20) ? true
         : (roll == 1)  ? false
         : (Bonus + roll >= DC);' \
'    return (Bonus + roll >= DC);'

A_LINES="$(mktemp -t natural_save_a)" || _check_die 2 "no temp file"
B_LINES="$(mktemp -t natural_save_b)" || _check_die 2 "no temp file"
trap 'rm -f "$A_LINES" "$B_LINES"' EXIT

# Run one session and keep its distinct save lines in <outfile>. The log is
# paged with overlapping windows, so sort -u drops repeats of one real roll.
session() { # <outfile> <keys> <roll> [dc]
    local out="$1" keys="$2" roll="$3" dc="${4:-}"
    if [ -n "$dc" ]; then
        INCURSION_LOAD="$FIXTURE" INCURSION_FORCE_SAVE_ROLL="$roll" \
            INCURSION_FORCE_SAVE_DC="$dc" check_run "$keys" "$SEED"
    else
        INCURSION_LOAD="$FIXTURE" INCURSION_FORCE_SAVE_ROLL="$roll" \
            check_run "$keys" "$SEED"
    fi
    check_screens '*messages*'
    grep -h "Save: 1d20 (" "${CHECK_SCREENS[@]}" 2>/dev/null |
        sed -E 's/^[[:space:]]*\|[[:space:]]*//; s/[[:space:]]*\|[^|]*$//' |
        sort -u > "$out"
}

echo "--- session A: natural 20 against DC 27 guardian runes ---"
session "$A_LINES" tools/keys/natural-save-runes.keys 20
echo "--- session B: natural 1 against forced DC 1 ---"
session "$B_LINES" tools/keys/natural-save-tangle.keys 1 1

A_HITS="$(grep -E "Save: 1d20 \(20\).* vs DC 27 \[" "$A_LINES")"
B_HITS="$(grep -E "Save: 1d20 \(1\) .*= *[0-9]+ vs DC 1 \[" "$B_LINES")"

[ -n "$A_HITS" ] || _check_die 2 "session A shows no roll-20-vs-DC-27 save line; the forced roll never reached a DC 27 save."
[ -n "$B_HITS" ] || _check_die 2 "session B shows no roll-1-vs-DC-1 save line; the forced roll or DC never reached a save."

# Session B: the total must reach the DC, or the line cannot tell the rule from a comparison.
B_BAD_TOTAL="$(printf '%s\n' "$B_HITS" | sed -E 's/.*= *(-?[0-9]+) vs DC ([0-9]+) .*/\1 \2/' | awk '$1 < $2')"
[ -z "$B_BAD_TOTAL" ] || _check_die 2 "session B has a line whose total is below its DC; it cannot separate the rule from a bare comparison."

echo
echo "session A lines (roll 20, DC 27): $(printf '%s\n' "$A_HITS" | wc -l | tr -d ' ')"
echo "session B lines (roll 1, DC 1):   $(printf '%s\n' "$B_HITS" | wc -l | tr -d ' ')"

A_BAD="$(printf '%s\n' "$A_HITS" | grep -v "\[success\]")"
if [ -n "$A_BAD" ]; then
    echo
    echo "FAIL: a natural 20 against DC 27 did not read [success]:"
    printf '%s\n' "$A_BAD" | sed 's/^/      /'
    exit 1
fi
B_BAD="$(printf '%s\n' "$B_HITS" | grep -v "\[failure\]")"
if [ -n "$B_BAD" ]; then
    echo
    echo "FAIL: a natural 1 with total at or above the DC did not read [failure]:"
    printf '%s\n' "$B_BAD" | sed 's/^/      /'
    exit 1
fi

echo
echo "PASS: every forced natural 20 read [success] and every forced natural 1 read [failure]."
exit 0
