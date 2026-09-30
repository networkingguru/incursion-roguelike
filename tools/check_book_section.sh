#!/bin/bash
# gate: live
# Regression check for books being listed under "Other Items" in the inventory,
# bd inc-twr9.
#
# THE DEFECT. Player::InvShowSlots lists the pack grouped by itemGroups[]
# (src/Managers.cpp:444), and the heading for a group is printed either by a
# special case in that function or, for everything else, by
# Lookup(ITypeNames, itemGroups[sortOrder(...)]) (src/Managers.cpp:557). A book
# is a T_BOOK. itemGroups[] had no T_BOOK entry, so sortOrder() fell through to
# its trailing 50 (src/Managers.cpp:452), the book landed in the T_ITEM group,
# and its heading printed as "Other Items" (src/Managers.cpp:552-553). The name
# table never needed touching: ITypeNames already had { T_BOOK, "Books" }
# (src/Tables.cpp:1031), it was simply never reached. Adding T_BOOK to
# itemGroups[] right after T_SCROLL gives the book its own group and its own
# heading.
#
# THE ORACLE IS THE GAME'S OWN INVENTORY LISTING. Player::InvShowSlots prints
# the heading and the item rows itself, so both the section the book is filed
# under and the book's own name are read off one screen the game drew. The
# wizard-mode "Item Acquisition" browser (src/Debug.cpp:538) hands over a
# spellbook; the key script stows it in the pack and dumps the listing. Measured
# on seed 1, tools/keys/book-inventory-section.keys, src/Managers.cpp the only
# file different between the two builds:
#
#   book in the pack      before: Other Items / 11) spellbook [...]
#                         after:  Books       / 06) spellbook [...]
#
# THIS CHECK FAILS, AND DOES NOT SAY INCONCLUSIVE, WHEN IT FINDS NOTHING.
# The other checks in this directory distinguish "measured the wrong thing"
# from "the behaviour is wrong", because a dead session must not frame an
# innocent commit. Here both the inventory screen and the book are the whole
# measurement, and a book that does not appear in the pack listing under ANY
# heading is exactly the defect this check is for -- the item never arrived, or
# the listing never showed it. So a missing screen or a missing book is a FAIL,
# not an inconclusive run.
#
# Usage: tools/check_book_section.sh    (0 pass, 1 fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/book-inventory-section.keys
SEED=1

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

# A run directory of this check's own, so two checks run at once cannot share
# one save/, and the dumps this check reads are the ones this run wrote.
RUNBASE="${INCURSION_RUN_DIR:-$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-check-book-section}"

# The pinned options file, not the live Options.Dat, which the owner's play
# rewrites every session (tools/README.md, trap 2).
OUT="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
       INCURSION_RUN_DIR="$RUNBASE" tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
S="$RUN/logs/screens"

DUMP="$(ls "$S"/*-book-in-inventory.txt 2>/dev/null | head -1)"
if [ -z "$DUMP" ]; then
    echo "FAIL: the session produced no inventory dump, so it never reached the"
    echo "      screen under test. Run dir: $RUN"
    echo "$OUT" | sed 's/^/      /'
    exit 1
fi

# The line the game printed for the acquired book. A spellbook's mechanical
# name is lowercase with a bracket after it; the wizard acquisition list drew a
# spellbook, so the pack must show one. If none is here, the book is missing
# from the listing -- the defect, or the acquisition never happened.
BOOKLINE="$(grep -a -m1 "spellbook \[" "$DUMP" | tr -cd '\40-\176\n')"
if [ -z "$BOOKLINE" ]; then
    echo "FAIL: no spellbook line appears in the inventory listing, so the book"
    echo "      is not in the pack listing at all. Run dir: $RUN"
    echo "      Dump: $DUMP"
    exit 1
fi

# The heading is the nearest non-indented line ABOVE the book. Item rows are
# printed as "  %02d) name" (src/Managers.cpp:561), so a row starts with two
# spaces and a heading starts at column 0. Walk up from the book until the
# first such line; that is the section the game filed the book under.
HEADING="$(awk -v book="$BOOKLINE" '
    { lines[NR] = $0 }
    END {
        target = 0
        for (n = 1; n <= NR; n++)
            if (lines[n] == book) { target = n; break }
        if (target == 0) exit
        for (n = target - 1; n >= 1; n--) {
            l = lines[n]
            if (l == "") continue
            if (l ~ /^ /) continue
            if (l ~ /^===/) continue
            sub(/[[:space:]][[:space:]].*$/, "", l)
            print l
            exit
        }
    }
    ' "$DUMP")"

if [ -z "$HEADING" ]; then
    echo "FAIL: could not find a section heading above \"$BOOKLINE\" in the"
    echo "      inventory listing. Run dir: $RUN"
    echo "      Dump: $DUMP"
    exit 1
fi

if [ "$HEADING" = "Books" ]; then
    echo "PASS: the book is listed under its own \"Books\" heading."
    echo "      $BOOKLINE"
    echo "      seed $SEED, $DUMP"
    exit 0
fi

echo "FAIL: the book is listed under \"$HEADING\", not \"Books\"."
echo "      $BOOKLINE"
if [ "$HEADING" = "Other Items" ]; then
    echo "      T_BOOK is missing from itemGroups[] (src/Managers.cpp:444), so"
    echo "      sortOrder() (src/Managers.cpp:448) sends books to the trailing"
    echo "      T_ITEM group instead of the T_SCROLL-adjacent book group."
fi
echo "      Run dir: $RUN"
echo "      Dump: $DUMP"
exit 1
