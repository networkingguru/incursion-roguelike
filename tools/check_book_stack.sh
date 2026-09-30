#!/bin/bash
# Regression check for the two identical unidentified books that would not
# stack, bd inc-elhn.
#
# WHAT IS BEING PROVED. Item::operator== (src/Item.cpp) decides whether two
# items merge into one pack entry. Every item gets a fresh GenNum when it is
# created (src/Item.cpp:89), and two items from different generation groups are
# only allowed to stack when they are fully identified
# (KN_MAGIC|KN_PLUS|KN_BLESS). The switch that marks a type as "easy stacking"
# -- exempt from that identification requirement -- listed T_TOOL, T_FOOD,
# T_POTION and T_SCROLL but not T_BOOK, even though a book is as little
# distinguishable by generation as a scroll is. Two copies of the same
# unidentified book therefore took two inventory slots.
#
# THE ORACLE IS THE GAME'S OWN PACK SCREEN. Player::ItemMenu writes a stack as
# a count and a plural ("2 Potions of Detect Stairs"), so the merge is printed
# by the game, in words, on the inventory screen. The key script acquires two
# copies of one book and one copy of a second, all through wizard mode's
# "Acquire Unknown Item" so their Known is 0 and their GenNums differ. Measured
# on seed 1, tools/keys/book-stack.keys, src/Item.cpp the only file different
# between the two builds:
#
#   two "Mystic Aegis"   before: 11) ? spellbook [Mystic Aegis]
#                                12) ? spellbook [Mystic Aegis]   <- two entries
#                        after:  11) 2 ? spellbooks [Mystic Aegis]  <- one, count 2
#   one "Tome of Magic"  before: 13) ? spellbook [Tome of Magic]
#                        after:  12) ? spellbook [Tome of Magic]    <- own entry
#
# THE DIFFERENT BOOK IS NOT DECORATION. A "fix" that stacks every book with
# every other -- by ignoring iID -- would pass the first half and corrupt the
# inventory. The check demands the different book keep its own entry.
#
# A RUN THAT MEASURED NOTHING. The book list has no menu letters
# (TextTerm::AcquisitionPrompt, src/Term.cpp), so the key script walks to each
# book by name with @until/@expect. If the pack screen does not show both
# books, or is not the pack screen at all, the session says nothing about this
# bug and the check fails rather than passing on an empty comparison.
#
# Usage: tools/check_book_stack.sh    (0 pass, 1 fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
SAME="Mystic Aegis"
OTHER="Tome of Magic"

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
       tools/headless.sh tools/keys/book-stack.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
PACK="$run/logs/screens/0001-pack.txt"

if [ ! -f "$PACK" ]; then
    echo "FAIL: the session produced no pack screen, so the inventory was never"
    echo "      opened and nothing was measured."
    echo "$out" | sed 's/^/      /'
    echo "Run dir: $run"
    exit 1
fi

# The books must actually be on the pack screen. If either is missing the run
# did not acquire what this check is about.
if ! grep -qF "$SAME" "$PACK" || ! grep -qF "$OTHER" "$PACK"; then
    echo "FAIL: the pack screen does not show both \"$SAME\" and \"$OTHER\","
    echo "      so the acquisitions did not land. Nothing was measured."
    echo "Run dir: $run"
    exit 1
fi

# The unidentified marker is part of what makes this the bug: two books that
# the game had identified would stack through the fully-identified branch and
# say nothing about the missing easy-stack case.
if ! grep -q '? spellbook' "$PACK"; then
    echo "FAIL: the pack screen shows no unidentified book ('? spellbook'), so"
    echo "      the books were not acquired unknown. Nothing was measured."
    echo "Run dir: $run"
    exit 1
fi

fail=0

# 1. Two copies of the same book must be ONE entry, carrying quantity 2.
same_entries="$(grep -cE "^ *[0-9]+\) .*$SAME" "$PACK")"
if [ "$same_entries" -ne 1 ]; then
    echo "FAIL: two copies of the same unidentified book take $same_entries pack"
    echo "      entries, not 1 -- identical books do not stack."
    grep -E "^ *[0-9]+\) .*$SAME" "$PACK" | sed 's/^/      /'
    fail=1
elif ! grep -qE "^ *[0-9]+\) 2 .*$SAME" "$PACK"; then
    echo "FAIL: the single \"$SAME\" entry does not show a count of 2, so one"
    echo "      copy was lost rather than merged."
    grep -E "^ *[0-9]+\) .*$SAME" "$PACK" | sed 's/^/      /'
    fail=1
fi

# 2. The different book must keep its own entry.
other_entries="$(grep -cE "^ *[0-9]+\) .*$OTHER" "$PACK")"
if [ "$other_entries" -ne 1 ]; then
    echo "FAIL: the different book \"$OTHER\" takes $other_entries entries, not 1"
    echo "      -- the fix is collapsing distinct books together."
    grep -E "^ *[0-9]+\) .*$OTHER" "$PACK" | sed 's/^/      /'
    fail=1
fi

if [ "$fail" = 1 ]; then
    echo "Run dir: $run"
    exit 1
fi

echo "PASS: two identical unidentified books stack to one entry of 2, and a"
echo "      different book keeps its own entry."
echo "Run dir: $run"
exit 0
