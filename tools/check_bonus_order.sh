#!/bin/bash
# gate: live
# Status bonuses of one non-stacking type must total the same whatever order
# the status rows are read in (bd inc-t05z9).
#
# THE DEFECT. Creature::AddBonus keeps the larger of two positive bonuses of
# one type but adds a penalty to a negative total. So +1, +4 and -4 to Strength
# gave 0 when read as 1,4,-4 and +1 when read as 4,-4,1. The status rows of one
# nature are read in stati-list order, which nothing fixes (StatiSort compares
# Nature only; qsort is unstable). The fix reads them positives largest first,
# then penalties (ApplyAdjustRows, src/Values.cpp).
#
# THE SCENARIO. A frozen lizardfolk monk is loaded. INCURSION_BONUS_ORDER_PROBE
# gives him one permanent enhancement row on Strength per listed value, once, at
# game start. INCURSION_BONUS_ORDER_REVERSE=1 reverses the gathered rows before
# the sort, so the same rows are read in the opposite order. The character sheet
# is the oracle, and the engine's own logs/bonusorder.log names the read order.
#
#   no probe        the sheet's Strength: the baseline
#   1,4,-4          the sheet must show the baseline (the +4, then the -4)
#   1,4,-4 reversed the sheet must show the baseline again
#   2,3             the sheet must show the baseline + 3: bonuses of one type
#                   do not stack, the larger one counts
#
# A run pair whose last logged read orders are the same is exit 2, not a pass:
# the check then did not read the rows two ways.
#
# PROVED RED by --prove-red: the mutation applies the rows without sorting. The
# forward and reversed sheets then differ and this check exits 1.
#
# fact: character -- fixture lizardfolk-monk-seed1 (INCURSION_LOAD), no chargen
# fact: settings -- tools/fixtures/options-2026-08-22.dat (CHECK_OPTIONS)
# fact: the Strength rows and their values -- INCURSION_BONUS_ORDER_PROBE grants them at game start
# fact: the order the rows are read in -- INCURSION_BONUS_ORDER_REVERSE, confirmed by the logs/bonusorder.log read order of both runs
# fact: the Strength total -- the sheet line "STR: <n>", read relative to a baseline run of the same save
# fact: random rolls -- none feed Strength; one search turn passes and every total is compared with a baseline of the same save, so the check reads no seed
#
# Usage: tools/check_bonus_order.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
SUBJECT=tools/fixtures/chars/lizardfolk-monk-seed1.sav
KEYS=tools/keys/load-char-sheet.keys

[ -x ./incursion-headless ] || _check_die 2 \
    "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
[ -f "$SUBJECT" ] || _check_die 2 "the frozen subject $SUBJECT is missing."

# The sort is what the fix is. Disabling it applies the rows in gathered order.
check_mutation src/Values.cpp \
    'std::stable_sort(rows.begin(),rows.end(),AdjRowLarger);' \
    '(void)AdjRowLarger; /* mutation: sort disabled */'

mkdir -p "$CHECK_ROOT/logs/runs"

# play <probe list or ""> <reverse 0|1> -> sets STR and ORDER from one session.
STR=""; ORDER=""
play() {
    local probe="$1" reverse="$2" dir
    dir="$(mktemp -d "$CHECK_ROOT/logs/runs/bonus-order.XXXXXX")"
    export INCURSION_LOAD="$SUBJECT" INCURSION_RUN_DIR="$dir"
    if [ -n "$probe" ]; then export INCURSION_BONUS_ORDER_PROBE="$probe"; fi
    if [ "$reverse" = 1 ]; then export INCURSION_BONUS_ORDER_REVERSE=1; fi
    check_run "$KEYS" 1 >&2
    unset INCURSION_LOAD INCURSION_RUN_DIR INCURSION_BONUS_ORDER_PROBE INCURSION_BONUS_ORDER_REVERSE
    STR="$(grep -hoE 'STR: *[0-9]+' "$CHECK_RUN"/logs/screens/*sheet*.txt 2>/dev/null \
        | head -1 | grep -oE '[0-9]+')"
    [ -n "$STR" ] || _check_die 2 "no 'STR: <n>' on the sheet dump in $CHECK_RUN."
    ORDER=""
    if [ -n "$probe" ]; then
        [ -s "$CHECK_RUN/logs/bonusorder.log" ] || _check_die 2 \
            "the probe wrote no logs/bonusorder.log in $CHECK_RUN, so the read order is unknown."
        ORDER="$(tail -1 "$CHECK_RUN/logs/bonusorder.log" | sed -E 's/^rows ([^ ]*) .*/\1/')"
        local want got
        want="$(echo "$probe" | tr ',' '\n' | sort -n | tr '\n' ' ')"
        got="$(echo "$ORDER" | tr ',' '\n' | sort -n | tr '\n' ' ')"
        [ "$want" = "$got" ] || _check_die 2 \
            "the engine read rows [$ORDER], not the granted [$probe]; the probe did not grant them."
    fi
}

echo "Same-type status bonuses total the same in either read order (inc-t05z9)"
echo "options: $CHECK_OPTIONS   subject: $SUBJECT"
echo

play "" 0;      BASE="$STR"
play "1,4,-4" 0; FWD="$STR"; FWD_ORDER="$ORDER"
play "1,4,-4" 1; REV="$STR"; REV_ORDER="$ORDER"
play "2,3" 0;   STACK="$STR"

echo "  baseline Strength               $BASE"
echo "  rows 1,4,-4 read [$FWD_ORDER]   Strength $FWD"
echo "  rows 1,4,-4 read [$REV_ORDER]   Strength $REV"
echo "  rows 2,3                        Strength $STACK"

if [ "$FWD_ORDER" = "$REV_ORDER" ]; then
    _check_die 2 "could not establish two read orders: both runs read [$FWD_ORDER]."
fi

[ "$FWD" -eq "$BASE" ] && CHECK_EXPECTS=$((CHECK_EXPECTS+1)) || {
    echo "FAIL: read as [$FWD_ORDER], +1 +4 -4 gave Strength $FWD; want the baseline $BASE."
    CHECK_FAIL=1; }
[ "$REV" -eq "$BASE" ] && CHECK_EXPECTS=$((CHECK_EXPECTS+1)) || {
    echo "FAIL: read as [$REV_ORDER], +1 +4 -4 gave Strength $REV; want the baseline $BASE."
    CHECK_FAIL=1; }
[ "$STACK" -eq $((BASE + 3)) ] && CHECK_EXPECTS=$((CHECK_EXPECTS+1)) || {
    echo "FAIL: rows 2,3 gave Strength $STACK; want $((BASE + 3)) (the larger bonus, not the sum)."
    CHECK_FAIL=1; }

check_done "+1 +4 -4 to Strength gives the baseline in both read orders, and 2,3 gives +3 (inc-t05z9)"
