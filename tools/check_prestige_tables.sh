#!/bin/bash
# Regression check for the prestige-class level tables, bd inc-tek.8.3
# findings PA-03-F16 and PA-03-F17.
#
# Each prestige class states its saves and its defence track three times: in
# the header line of its description, in the Flags/Def: fields the engine
# actually reads, and in the level table it prints to the player. In five
# classes the table disagreed with the other two, so a player reading the class
# screen was told numbers the character would never get.
#
#   Alienist, Loremaster, Sentinel   two save columns transposed   (PA-03-F16)
#   Blackguard, Twilight Huntsman    a defence track twice as fast (PA-03-F17)
#
# The tables were corrected, because the header and the field agree against
# them in every case. This asserts the corrected rows on the screen a player
# actually reads them from -- the [P]restige Classes menu.
#
# What the right numbers are is not a matter of taste. src/Tables.cpp:100-116
# gives the two save tracks, src/Values.cpp:393-397 picks between them from
# CF_GOOD_FORT/CF_GOOD_REF/CF_GOOD_WILL, and src/Values.cpp:398 computes the
# defence bonus as class level / DefMod, where DefMod is the N of "Def: 1/N"
# (src/yygram.cpp:3956).
#
# Usage: tools/check_prestige_tables.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/prestige-tables.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCREENS="$RUN/logs/screens"

# A session that measured nothing must never read as a pass -- inc-loa.3.
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi
if [ ! -d "$SCREENS" ]; then
    echo "FAIL: no screen dumps at $SCREENS"
    exit 1
fi

fail=0

# Every assertion is a table row, given as "level def fort refl will" with
# single spaces. The screen is squeezed to single spaces before matching, so
# the column widths in the .irh file can change without breaking this.
#
# check <dump> <banner the dump must show> <row> [<row>...]
check() {
    local dump="$1" banner="$2"; shift 2
    local file="$SCREENS/$(ls "$SCREENS" | grep -- "-$dump\.txt$" | head -1)"
    local squeezed row

    if [ ! -f "$file" ]; then
        echo "FAIL: $dump was never dumped"
        fail=1
        return
    fi

    # Guard first, assertion second: if the menu letters moved because a
    # prestige class was added to lib/, the DOWN counts in the key script
    # land on the wrong class and every row below would fail for the wrong
    # reason. Say so instead.
    if ! grep -q "$banner" "$file"; then
        echo "INCONCLUSIVE: $dump does not show \"$banner\" -- the key script's"
        echo "              DOWN counts have rotted; fix them before reading this."
        fail=1
        return
    fi

    squeezed="$(sed 's/|//g; s/  */ /g' "$file")"
    for row in "$@"; do
        if echo "$squeezed" | grep -qF " $row "; then
            echo "  ok: $dump  $row"
        else
            echo "FAIL: $dump has no row \"$row\""
            fail=1
        fi
    done
}

# PA-03-F16. Fortitude and Will are the good tracks; Reflex is the poor one,
# which is what CF_GOOD_FORT + CF_GOOD_WILL and the header "FrW" both say.
check alienist "THE ALIENIST" \
    "1 +0 +2 +0 +2" "2 +0 +3 +0 +3" "3 +0 +3 +1 +3" "4 +1 +4 +1 +4"

# Will alone is good: CF_GOOD_WILL, header "frW".
check loremaster "THE LOREMASTER" \
    "1 +0 +0 +0 +2" "2 +0 +0 +0 +3" "3 +0 +1 +1 +3" "4 +1 +1 +1 +4"

# Reflex alone is good: CF_GOOD_REF, header "fRw". This table used to stop
# after four rows and print "..." -- PA-03-F37. It now runs to 10, which is
# what the class runs to: it declares no TOTAL_CLASS_LEVELS, and
# src/Create.cpp:2440 gives every CF_PRESTIGE class 10 levels by default.
check sentinel "THE SENTINEL" \
    "1 +0 +0 +2 +0" "2 +0 +0 +3 +0" "3 +0 +1 +3 +1" "4 +1 +1 +4 +1" \
    "5 +1 +1 +4 +1" "6 +1 +2 +5 +2" "7 +1 +2 +5 +2" "8 +2 +2 +6 +2" \
    "9 +2 +3 +6 +3" "10 +2 +3 +7 +3"

# PA-03-F17. Def: 1/4 means one point per four class levels, so the column
# must read +0 +0 +0 +1 +1 ... and not the 1/2 track it used to print.
check blackguard "THE BLACKGUARD" \
    "1 +0 +2 +0 +0" "3 +0 +3 +1 +1" "4 +1 +4 +1 +1" "5 +1 +4 +1 +1"

# Also Def: 1/4, against a table that used to print the 1/3 track. Level 7 is
# the row that proves it: +1 here, +2 before.
check twilight "THE TWILIGHT HUNTSMAN" \
    "1 +0 +2 +2 +0" "4 +1 +4 +4 +1" "7 +1 +5 +5 +2" "8 +2 +6 +6 +2"

if [ "$fail" = 0 ]; then
    echo "PASS: all five prestige tables print the saves and defence their classes grant"
    exit 0
fi
exit 1
