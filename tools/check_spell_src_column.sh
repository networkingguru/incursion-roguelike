#!/bin/bash
# gate: live
# inc-ympc: does the Spell Manager show "inn" in its Src column for an innate
# spell?
#
# THE CHARACTER is tools/fixtures/chars/underdark-deepgnome-seed3-opt0818.sav, a
# deep gnome whose racial spells (Cause Blindness, Passwall, Blur ...) carry
# SP_INNATE and no source bit. tools/check_spell_tags.sh covers the dual-source
# rows; this check covers the innate row and the box width.
#
# PROVED RED with --prove-red: the mutation makes SpellSrcColumnName return ""
# for an innate entry, so the "inn" assertion fails.
#
# Usage: tools/check_spell_src_column.sh [--prove-red]
#   0 every expectation holds   1 one fails   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/underdark-deepgnome-seed3-opt0818.sav
KEYS=tools/keys/spell-src-column.keys
SEED=4

check_mutation src/Managers.cpp \
'        default:        return (flags & SP_INNATE) ? "inn" : "";' \
'        default:        return "";'

[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE to load."
[ -f "$KEYS" ]    || _check_die 2 "no $KEYS to run."

export INCURSION_LOAD="$FIXTURE"
check_run "$KEYS" "$SEED"

check_screens '*-cast-menu'
check_expect "Spell                  Src Mana" "the header puts Src between Spell and Mana"
check_expect "Cause Blindness        inn" "an innate spell's row has Src inn beside the bare name"
check_reject "(inn)" "the innate row draws no name prefix"
for f in "${CHECK_SCREENS[@]}"; do
    wide="$(awk 'length($0) > 80 { n++ } END { print n + 0 }' "$f")"
    if [ "$wide" -ne 0 ]; then
        echo "  FAIL  $wide line(s) wider than 80 columns in $f"
        CHECK_FAIL=1
    else
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
        echo "  ok    no line wider than 80 columns in $(basename "$f")"
    fi
done

check_done "an innate spell shows inn in the Src column and the box stays 80 wide"
