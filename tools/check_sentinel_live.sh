#!/bin/bash
# Does the Sentinel's printed level table match what the Sentinel actually
# grants? bd inc-tek.8.3 finding PA-03-F16, and the mission test for bd
# inc-cso.
#
# THE DEFECT. lib/prestige.irh printed the Sentinel's save columns in the wrong
# order, so its table promised a good Fortitude save the class does not grant
# and a poor Reflex save it does. The class's own Flags field says
# CF_GOOD_REF, and src/Values.cpp:393-397 reads that field and nothing else.
#
# WHY THIS CHECK IS NOT tools/check_prestige_tables.sh. That one reads the
# table off the prestige menu. It proves the corrected text is on the screen.
# It cannot prove the text is TRUE, because it never makes a Sentinel -- and a
# table can be self-consistently wrong. This one makes one, four levels deep,
# and reads the numbers back out of the engine.
#
# THE ORACLE. The character sheet breaks every total down by class:
#     Fortitude   +2 (Rogue +1/ Sentinel +1)
# src/Sheet.cpp builds that from the same per-class save track the rules use,
# so the parenthesised Sentinel term is the class's own contribution, stated
# by the engine, in numbers, beside a second class that is keeping it honest.
#
# THE ROW UNDER TEST is the table's 4th: Def +1, Fort +1, Ref +4, Will +1.
#
# WHAT EACH HALF OF THE EVIDENCE CARRIES. Only check_prestige_tables.sh was red
# before the fix -- the defect was in the printed table, so a check that reads
# the engine could not have been. This one pins the engine end, and that is
# what stops the disagreement from being "fixed" the other way round some day,
# by editing the table to match a wrong belief about the class. The two
# together say the table and the engine agree, and name the number they agree
# on. src/Tables.cpp:100-103 and :113-116 are where +4 and +1 come from:
# GoodSave[4] is +4 and PoorSave[4] is +1, selected by the class's CF_GOOD_REF
# flag at src/Values.cpp:393-397.
#
# Usage: tools/check_sentinel_live.sh     (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/prestige-sentinel.keys
fail=0

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SHEET="$RUN/logs/sheet.txt"

if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi
if [ ! -f "$SHEET" ]; then
    echo "FAIL: the sheet was never written to $SHEET"
    exit 1
fi

# Guard first. If the character never took the class, every assertion below
# would pass or fail for the wrong reason.
if ! grep -q "Sentinel 4" "$SHEET"; then
    echo "FAIL: the character is not a 4th-level Sentinel, so the script has rotted."
    grep -m1 -A1 "^Class" "$SHEET"
    exit 1
fi
echo "  ok: the character holds the class -- $(grep -m1 'Sentinel 4' "$SHEET" | tr -s ' ')"

# The four columns of the table's 4th row, each read out of a different line of
# the sheet, each naming Sentinel separately from the core class.
check() {
    if grep -q "$2" "$SHEET"; then
        echo "  ok: $1 -- $(grep -m1 "$2" "$SHEET" | tr -s ' ')"
    else
        echo "FAIL: $1"
        echo "      the sheet says: $(grep -m1 "^$3" "$SHEET" | tr -s ' ')"
        fail=1
    fi
}

check "Fortitude: the table says the Sentinel adds +1" "Sentinel +1, *+3 Wis\|Fortitude .*Sentinel +1" "Fortitude"
check "Reflex: the table says the Sentinel adds +4"    "Reflex .*Sentinel +4"    "Reflex"
check "Will: the table says the Sentinel adds +1"      "Will .*Sentinel +1"      "Will"
check "Defence: the table says the Sentinel adds +1"   "+1 Sentinel,"            "  (base 10"

if [ "$fail" = 0 ]; then
    echo "PASS: a live 4th-level Sentinel grants the +1/+1/+4/+1 its table prints"
    exit 0
fi
exit 1
