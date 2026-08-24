#!/bin/bash
# Does the Staff of the Abyss advertise only the spells it actually grants?
# Finding PA-08-F7 of bd inc-tek.8.8.
#
# THE DEFECT. The staff's page named twelve spells and its STAFF_SPELL_LIST
# grants nine. The three extras were cacodaemon, death knell and ensnarement.
#
# WHY THE PROSE LOSES HERE, against this partition's usual rule that the page
# wins. The three names are not spells the script forgot to grant. They are
# names with nothing behind them:
#   * Ensnarement has no definition anywhere in lib/. There is no such spell.
#   * Cacodemon has none either. It is commented out at lib/sp_books.irh:504
#     and again inside the Evil domain's commented block at lib/domains.irh:266.
#   * Death Knell exists only as a stub: lib/pspells.irh:1781 is
#     Effect "Death Knell" : EA_NOTIMP { }.
# Honouring the page would mean writing two spells from nothing and finishing a
# third that upstream itself marked not-implemented. That is a feature, not a
# prose fix. The feature is tracked as bd inc-tek.26, and the live-defect half
# -- classes and monsters that still hand out the Death Knell stub -- as bd
# inc-tek.27. So the three names come off the page and the script is untouched.
#
# THE ORACLE. This change moves no behaviour, so no behavioural check is
# possible and none is faked here. What CAN be checked, and what matters, is
# what the PLAYER reads: the item description screen, reached from Inventory
# Mode with 'x' (src/Managers.cpp:751-754), which renders the entity's Desc
# through Item::Describe (src/Help.cpp:3405-3408). This check drives the game
# to that screen and counts the spell names the game itself printed. Reading
# lib/m_items.irh with grep would prove only that a file changed, which is not
# the same claim.
#
# Usage: tools/check_staff_abyss_spell_list.sh  (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

# The nine spells the STAFF_SPELL_LIST actually grants, in the order the page
# names them. Kept here in full rather than as a count, so that a page which
# named nine of the WRONG spells could not pass.
WANT="bestow curse|burning blood|contagion|deeper darkness|desecrate|dire charm|enervation|unholy blight|wall of fire"

# The three that came off the page. Spelled as the page spelled them: the Desc
# wrote "cacodaemon" where lib/sp_books.irh writes "Cacodemon", which is one
# more sign that nothing connected the name to an implementation.
GONE="cacodaemon
death knell
ensnarement"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/staff-abyss-spell-list.keys "$SEED" 2>&1)"
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
# the closing one and join them into one string. Joining is the point: Box
# hard-wraps, so the sentence this check counts is spread over three screen
# rows and no grep of the raw dump could match it.
#
# The last column of the box interior is the scrollbar. UpdateScrollArea draws
# '^' and 'v' there, over the padding, and it abuts the text when a wrapped
# line happens to be full width -- "it grants access to thev" is a real row
# from this run. Strip that one character when it is one of those two arrows.
box_text() { # <screen dump> -> the box's text on one line
    awk '
      /#-+#/ { if (!seen) { match($0,/#-+#/); L=RSTART; W=RLENGTH; seen=1; next }
               else exit }
      seen  { s = substr($0, L+1, W-2)
              c = substr(s, length(s), 1)
              if (c == "^" || c == "v") s = substr(s, 1, length(s)-1)
              gsub(/^ +| +$/, "", s)
              if (s != "") printf "%s ", s }
    ' "$1"
}

ls "$scr"/*-desc-*.txt >/dev/null 2>&1 || {
    echo "INCONCLUSIVE: the session dumped no description screens. Run: $run"
    exit 2
}

# The page runs to about a hundred rows and the box shows forty, so the session
# dumps it six times at six-row steps. Take the FIRST dump that holds the spell
# sentence whole; the others start or end inside it.
title=""
sentence=""
for f in "$scr"/*-desc-*.txt; do
    t="$(box_text "$f")"
    case "$t" in *"Staff +2 Of The Abyss"*) [ -n "$title" ] || title="$t" ;; esac
    if [ -z "$sentence" ]; then
        s="$(printf '%s' "$t" | grep -o 'the following spells: [^.]*\.')"
        [ -n "$s" ] && { sentence="$s"; used="$f"; }
    fi
done

[ -n "$title" ] || {
    echo "INCONCLUSIVE: no description box in this session names a Staff +2 of"
    echo "              the Abyss, so the wrong item was described or none was."
    echo "              Screens: $scr"
    exit 2
}
[ -n "$sentence" ] || {
    echo "INCONCLUSIVE: no dump holds the staff's spell sentence entire, so"
    echo "              there was nothing to count. Every dump either starts or"
    echo "              ends inside it. Screens: $scr"
    exit 2
}

# " and " joins the last two names and ", " joins the rest. None of the nine
# contains either separator inside itself, so this splits cleanly.
names="$(printf '%s' "$sentence" |
         sed 's/^the following spells: //; s/\.$//; s/ and /, /g' |
         tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$')"
count="$(printf '%s\n' "$names" | wc -l | tr -d ' ')"
joined="$(printf '%s\n' "$names" | paste -sd'|' -)"

rc=0
while IFS= read -r g; do
    [ -n "$g" ] || continue
    if printf '%s' "$sentence" | grep -qi "$g"; then
        echo "FAIL: the page still advertises '$g', which no STAFF_SPELL_LIST"
        echo "      entry grants and which lib/ never defines."
        rc=1
    fi
done <<< "$GONE"

if [ "$joined" != "$WANT" ]; then
    echo "FAIL: the page does not name the nine spells the staff grants."
    echo "      wanted: $WANT"
    echo "      got:    $joined"
    echo "      Screen: ${used:-none}"
    rc=1
fi

if [ "$rc" = 0 ]; then
    echo "  ok: the Staff of the Abyss advertises $count spells, and they are the"
    echo "      nine its STAFF_SPELL_LIST grants."
    echo "      page: $sentence"
    echo "      read off $used"
fi
exit $rc
