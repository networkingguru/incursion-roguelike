#!/bin/bash
# Does the Staff of Winter carry the weapon quality its own page names?
# Finding PA-08-F6 of bd inc-tek.8.8.
#
# THE DEFECT. The staff's page (lib/m_items.irh) says "A Staff of Winter acts
# as a <14>+2 quarterstaff of weakening<7>". Its script gave it WQ_NUMBING.
# Weakening damages Strength and numbing damages Dexterity
# (src/Tables.cpp:1831-1832), so the player was promised one ability score and
# given another. The script is the slip and now says WQ_WEAKENING.
#
# WHY THE SCRIPT LOSES HERE, and not the page. WQ_WEAKENING and WQ_NUMBING are
# adjacent entries in the same table (src/Tables.cpp:1831-1832, and
# inc/Defines.h:2161-2162 numbers them 37 and 38 with a comment that their
# order must be kept). This partition has already produced one confirmed slip
# of exactly that shape: the Ring of Water Elemental Command took MA_FIRE from
# the line beside MA_WATER (commit c7f8b8b). One line up or down in a table
# read by eye is a slip with a known precedent here; a page that names a
# quality in plain words is not.
#
# THE ORACLE is the item description screen -- Inventory Mode, cursor on the
# item, 'x' (src/Managers.cpp:751-754). It prints the entity's page and then
# the item's weapon qualities, so both halves of the contradiction land on one
# screen and the check reads them off the same box.
#
# IT CANNOT BE THE ITEM'S NAME. The entity carries EF_HIDEQUAL. That flag does
# one thing and one thing only: it makes Item::xName skip the whole
# quality-word loop (src/Message.cpp:1241), so the staff is called "Staff +2
# of Winter" and never "Staff +2 of numbing". The description screen is a
# different function -- QItem::Describe, src/Help.cpp:3508-3524 -- and has no
# EF_HIDEQUAL test at all, so it still prints "Numbing:" or "Weakening:" and
# the quality's paragraph beneath it. A name-based check would have shown
# nothing either side of the fix.
#
# IT CANNOT BE BEHAVIOUR EITHER, not cheaply. Both qualities inflict 1d6
# points of ability damage on a hit against a save; only the ability differs.
# Telling them apart by play would mean landing hits and reading STR against
# DEX on the victim, which is a long random walk to reach a fact the
# description screen states outright.
#
# Usage: tools/check_staff_winter_quality.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/staff-winter-quality.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script could not find something on screen. Run: $run"
    exit 2
fi

scr="$run/logs/screens"

# The description box is drawn by TextTerm::Box, which sizes itself to its
# longest line (src/TextTerm.cpp:452-455), so its columns move when its text
# changes -- and this fix changes its text. Find the box by its own top border
# rather than by counting columns, then read every row between that border and
# the closing one and join them into a single string. Joining is the point:
# Box hard-wraps its text, so any phrase long enough to be worth asserting is
# split across two screen rows and no grep of the raw dump could match it.
# A trailing '^' or 'v' is the scrollbar arrow, not text.
box_text() { # <screen dump> -> the box's text on one line
    awk '
      /#-+#/ { if (!seen) { match($0,/#-+#/); L=RSTART; W=RLENGTH; seen=1; next }
               else exit }
      seen  { s = substr($0, L+1, W-2)
              sub(/ +[\^v]$/, "", s)
              gsub(/^ +| +$/, "", s)
              if (s != "") printf "%s ", s }
    ' "$1"
}

top="$scr/0002-desc-top.txt"
bot="$scr/0003-desc-bottom.txt"
for f in "$top" "$bot"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: no screen dumped at $f"; exit 2; }
done

TOP="$(box_text "$top")"
BOT="$(box_text "$bot")"
BOTH="$TOP $BOT"

[ -n "$TOP" ] || {
    echo "INCONCLUSIVE: no description box on $top, so nothing was described."
    exit 2
}

# The acquisition list is walked by cursor and not by menu letter, so read the
# item's name back before believing anything the box says. A cursor that
# stopped one row early would otherwise describe a different staff.
case "$TOP" in
    *"Staff +2 Of Winter"*) ;;
    *) echo "INCONCLUSIVE: the description box does not name a Staff +2 of"
       echo "              Winter, so the session described the wrong item."
       echo "              Screen: $top"
       exit 2 ;;
esac

# Both halves of the contradiction must be readable, or a silent pass would
# mean only that the screen went blank. The page half:
case "$BOTH" in
    *"quarterstaff of weakening"*) ;;
    *) echo "INCONCLUSIVE: the box does not carry the staff's page, so the"
       echo "              sentence this finding is about was never rendered."
       echo "              Screens: $top $bot"
       exit 2 ;;
esac
# And the quality half. QItem::Describe prints nothing at all for a quality
# the character has not identified (src/Help.cpp:3509), and prints the
# entity's page only for an item known to be magical (src/Help.cpp:3405), so
# a session whose "Identify Whole Pack" did not take would show neither line
# and must not be read as a pass.
case "$BOTH" in
    *"Weakening: A weapon of weakening"*|*"Numbing: A weapon of numbing"*) ;;
    *) echo "INCONCLUSIVE: the box names no weapon quality at all, so the"
       echo "              staff was never identified and this session"
       echo "              measured nothing. Screens: $top $bot"
       exit 2 ;;
esac

rc=0
case "$BOTH" in
    *"Numbing: A weapon of numbing"*)
        echo "FAIL: the staff's page calls it a quarterstaff of weakening, and"
        echo "      the same screen gives it the numbing quality."
        echo "      $(echo "$BOTH" | grep -o 'Numbing: A weapon of numbing[^.]*\.')"
        rc=1 ;;
esac
case "$BOTH" in
    *"Weakening: A weapon of weakening inflicts 1d6 points of Strength ability damage"*) ;;
    *)  echo "FAIL: the staff does not carry the weakening quality its page names."
        echo "      Wanted: Weakening: A weapon of weakening inflicts 1d6 points"
        echo "              of Strength ability damage ..."
        echo "      Screens: $top $bot"
        rc=1 ;;
esac

if [ "$rc" = 0 ]; then
    echo "  ok: the Staff of Winter is a quarterstaff of weakening on both the"
    echo "      page and the quality line of its own description screen."
    # The two dumps overlap, so both may carry the same sentence. Print it once.
    echo "      page:    $(echo "$BOTH" | grep -o 'A Staff of Winter acts as a [^,]*,' | head -1)"
    echo "      quality: $(echo "$BOTH" | grep -o 'Weakening: A weapon of weakening[^.]*\.' | head -1)"
fi
exit $rc
