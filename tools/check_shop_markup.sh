#!/bin/bash
# gate: live
# Roark Ironbeard's asking price is capped: at most 3x the list price at the
# worst Diplomacy index (-10), and 2x at index 0. (bd inc-nel5)
#
# Item::getShopCost (src/Social.cpp) multiplies the list price by
# ShopPrices[index + 10] / 100 for an M_SELLER. This check reads the asking
# price of five items (a dagger, a +1 long sword, a scroll of *identify* (Identify;scroll is fixed-price since inc-icp3), a potion
# of true-healing, a +5 ring mail) at every index -10..+30, and at the index the
# loaded character really gets ("natural").
#
# THE ORACLE is INCURSION_SHOP_MARKUP_PROBE (src/ShopMarkupProbe.cpp), run from
# Game::Play() (src/Main.cpp). It sets ShopIndexOverride (the test hook in
# getShopCost), asks Roark's price and logs, through Error():
#   SHOP_MARKUP_PROBE item=<label> index=<i|natural> list=<n> ask=<n>
# FAILS (1) when any ask > 3*(list+1) (list is truncated, so the true list is below list+1), when
# at index 0 ask is outside 2*list +- max(1, list/100), or when an item's list
# price differs between its lines. A missing or unparsable line is
# INCONCLUSIVE (2), never a pass.
#
# Usage: tools/check_shop_markup.sh                  (0 pass, 1 fail, 2 inconclusive)
#        tools/check_shop_markup.sh --prove-red table (0 when the old table goes red)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
SEED=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav

if [ "$CHECK_PROVE_RED" = 1 ] && [ "${CHECK_ARGS[0]:-}" != table ]; then
    _check_die 2 "--prove-red needs the site name: table"
fi

# "from" is the text now in the file; "to" is the old table, verbatim.
_from=$(cat <<'EOF_FROM'
        /* -10 to -6*/
        300, 290, 280, 270, 260,

        /* -5 to -1*/
        250, 240, 230, 220, 210,

        /* 0 to +4 */
        200, 195, 190, 185, 180,

        /* +5 to +9 */
        175, 170, 165, 160, 155,

        /* +10 to +14 */
        150, 147.5, 145, 142.5, 140,

        /* +15 to +19 */
        137.5, 135, 132.5, 130, 127.5,

        /* +20 to +24 */
        125, 123.5, 122, 120.5, 119,

        /* +25 to +30 */
        117.5, 116, 114.5, 113, 111.5, 110 };
EOF_FROM
)
_to=$(cat <<'EOF_TO'
        /* -10 to -6*/
        5000, 4750, 4500, 4250, 4000,

        /* -5 to -1*/
        3750, 3500, 3250, 3000, 2750,

        /* 0 to +4 */
        2500, 2250, 2000, 1500, 1000,

        /* +5 to +9 */
        900, 800, 700, 600, 500,

        /* +10 to +14 */
        450, 400, 350, 300, 250,

        /* +15 to +19 */
        225, 200, 190, 180, 170,

        /* +20 to +24 */
        160, 155, 150, 145, 140,

        /* +25 to +30 */
        135, 130, 125, 123, 122, 120 };
EOF_TO
)
check_mutation src/Social.cpp "$_from" "$_to"

ITEMS="dagger long_sword+1 scroll_star_identify potion_true_healing ring_mail+5"
INDEXES="-10 -9 -8 -7 -6 -5 -4 -3 -2 -1 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 natural"

INCURSION_SHOP_MARKUP_PROBE=1 check_run tools/keys/load-char-sheet.keys "$SEED"
LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 "the run logged nothing. The probe reports through Error()."
CLEAN="$(grep -v '^    ' "$LOG")"
echo "specimen: $LOG"

_val() { # <line> <name>
    printf '%s\n' "$1" | grep -oE "(^| )$2=[^ ]+" | head -1 | sed -E "s/^ ?$2=//"
}
_get() { # <item> <index> <field> -> value; dies 2 when missing
    local line v
    line="$(printf '%s\n' "$CLEAN" | grep -F "SHOP_MARKUP_PROBE item=$1 index=$2 " | head -1)"
    v="$(_val "$line" "$3")"
    case "$v" in ''|*[!0-9]*) _check_die 2 "missing or unparsable $3 for item=$1 index=$2: ${line:-no line}" ;; esac
    echo "$v"
}

nat="$(printf '%s\n' "$CLEAN" | grep -F 'SHOP_MARKUP_PROBE natural index=' | head -1)"
[ -n "$nat" ] || _check_die 2 "no 'SHOP_MARKUP_PROBE natural index=' line"
echo "$nat"

FAIL=0
printf '%-22s %s\n' item "list/ask at -10, 0, +10, +20, +30, natural"
for it in $ITEMS; do
    row=""
    list0=""
    for ix in $INDEXES; do
        l="$(_get "$it" "$ix" list)"; a="$(_get "$it" "$ix" ask)"
        [ -n "$list0" ] || list0="$l"
        if [ "$l" != "$list0" ]; then
            echo "FAIL: $it list price changes with the buyer ($l at index $ix, $list0 at first line)."
            FAIL=1
        fi
        if [ "$a" -gt $((3 * (l + 1))) ]; then
            echo "FAIL: $it index $ix: ask $a is more than 3x (list $l + 1)."
            FAIL=1
        fi
        if [ "$ix" = 0 ]; then
            tol=$((l / 100)); [ "$tol" -ge 1 ] || tol=1
            if [ "$a" -lt $((2 * l - tol)) ] || [ "$a" -gt $((2 * l + tol)) ]; then
                echo "FAIL: $it index 0: ask $a is not 2x list $l (+-$tol)."
                FAIL=1
            fi
        fi
        case "$ix" in -10|0|10|20|30|natural) row="$row  $ix:$l/$a" ;; esac
    done
    printf '%-22s%s\n' "$it" "$row"
done

if [ "$FAIL" -ne 0 ] || [ "$CHECK_FAIL" -ne 0 ]; then
    echo
    echo "FAIL: Roark's markup is above the cap."
    exit 1
fi
echo
echo "PASS: Roark's markup stays within 3x list, and is 2x at index 0."
exit 0
