#!/bin/bash
# Does the Ring of Item Preservation's page describe what the ring actually
# does? Finding PA-08-F9 of bd inc-tek.8.8.
#
# THE DEFECT. The page promised that "upon the death of the wearer, or if the
# wearer is rendered unconscious or paralyzed, they transport any items the
# wearer carries into a specially prepared extradimensional space", and that
# "these items can later be retrieved by the merchant guild or family the
# merchant works for using powerful magical rituals". None of that happens.
# The whole META(POST(EVICTIM(EV_DEATH))) handler that would have done it sits
# inside #if 0 (lib/m_items.irh:4991-5002).
#
# THE RING IS NOT INERT, WHICH IS WHY THE HANDLER WAS NOT SIMPLY ENABLED. The
# finding claimed the ring does nothing. That is wrong. The registration line
# -- xval: TRAP_EVENT; yval: POST(EVICTIM(EV_DEATH)) -- sits OUTSIDE the
# #if 0, and two live behaviours read it:
#   * lib/wspells.irh:3518. Apportation, the wizard spell that teleports one
#     item out of a creature's inventory into the caster's hands, refuses
#     against a wearer: HasEffStati(TRAP_EVENT,$"Item Preservation") sends it
#     to "The <hObj> flickers briefly." That is a real ward, and it is the
#     sentence the page now carries.
#   * lib/alchemy.irh:740. Dunking the ring in acid makes the acid and the
#     flask "vanish to another plane", which is the ring's identification
#     clue.
# Brian ruled on 2026-08-24 that the PAGE is corrected to match, and that the
# handler stays inside its #if 0. Finishing the feature is bd inc-tek.28,
# which also records why re-enabling it as written would be wrong.
#
# THE ORACLE, and why it is not grep. This change moves no behaviour, so a
# behavioural check is impossible and none is faked here. What can be checked,
# and what matters, is the page as the GAME renders it: reading lib/m_items.irh
# with grep would prove that a file changed, which is a different claim. The
# item description screen is reached from Inventory Mode with 'x'
# (src/Managers.cpp:751-754) and prints the entity's Desc through
# Item::Describe (src/Help.cpp:3405-3408).
#
# Usage: tools/check_ring_preservation_page.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

# Phrases the page must no longer print. Each is the false promise itself, not
# a word that happens to appear in it, and none contains punctuation: the box
# hard-wraps and joining its rows can leave a space before a comma or a full
# stop, so a pattern with punctuation in it could fail for the wrong reason.
#
# The last four are the second paragraph, which Brian ruled out on 2026-08-24
# as a follow-up to the same finding. Every sentence in it rested on the
# absent handler: it promised the ring preserves a wearer's items "for their
# (hopeful) resurrection", it described guilds recovering items "sequestered
# by the ring's magic", and it concluded the ring is of little use to a player
# character -- which is false, because the Apportation ward works for whoever
# wears the ring.
GONE="upon the death of the wearer
rendered unconscious or paralyzed
into a specially prepared extradimensional space
retrieved by the merchant guild or family
murder merchants and shop-keepers in order to loot the goods
Powerful NPC adventurers also sometimes wear these rings
deterrants against theft-by-murder
hopeful) resurrection
sequestered by the ring's magic"

# Phrases the page must print. The first is the true behaviour -- the ward
# that Apportation runs into. The second is the deterrent theme, which the
# ruling kept, re-aimed from murder-and-loot at the theft the ring does stop.
WANT="hold the wearer's possessions fast against any magic that would spirit them away
deterrants to those who would rob merchants and shop-keepers"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/ring-preservation-page.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script could not find something on screen. Run: $run"
    exit 2
fi

scr="$run/logs/screens"
ls "$scr"/*-desc-*.txt >/dev/null 2>&1 || {
    echo "INCONCLUSIVE: the session dumped no description screens. Run: $run"
    exit 2
}

# The description box is drawn by TextTerm::Box, which sizes itself to its
# longest line (src/TextTerm.cpp:452-455), so its columns move when its text
# changes -- and this fix changes its text. Find the box by its own top border
# rather than by counting columns, then read every row between that border and
# the closing one and join them into one string. Joining is the point: Box
# hard-wraps, so every sentence this check reads is spread over three or four
# screen rows and no grep of the raw dump could match one.
#
# The last column of the box interior is the scrollbar. UpdateScrollArea draws
# '^' and 'v' there, over the padding, and it abuts the text when a wrapped
# line happens to be full width. Strip that one character when it is one of
# those two arrows. Taken from tools/check_staff_abyss_spell_list.sh, which
# reads the same screen for the same reason.
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

# Take the FIRST dump whose box names the ring. The acquisition list is walked
# by cursor and the row above this ring is the Ring of Elemental Command
# (Water), so a cursor that stopped one row early would describe that instead
# and every "the page no longer says X" test below would pass for the wrong
# reason. The name is read back off the box's own title line.
page=""
used=""
for f in "$scr"/*-desc-*.txt; do
    t="$(box_text "$f")"
    case "$t" in
        *"Ring Of Item Preservation"*) page="$t"; used="$f"; break ;;
    esac
done

[ -n "$page" ] || {
    echo "INCONCLUSIVE: no description box in this session names a Ring of"
    echo "              Item Preservation, so the wrong item was described or"
    echo "              none was. Screens: $scr"
    exit 2
}

# The page must have arrived whole. Item::Describe prints the entity's Desc
# only for a KN_MAGIC item (src/Help.cpp:3405), so an unidentified ring would
# show the generic ring paragraph alone -- and that too would pass every
# "no longer says X" test below. The opening clause is not touched by this
# fix, so its presence proves the entity's own page is on screen.
case "$page" in
    *"These rings are highly valued by merchants"*) ;;
    *)  echo "INCONCLUSIVE: the box names the ring but does not carry the"
        echo "              entity's own page, so the item was probably not"
        echo "              identified. Screen: $used"
        exit 2 ;;
esac

rc=0
while IFS= read -r g; do
    [ -n "$g" ] || continue
    if printf '%s' "$page" | grep -qF "$g"; then
        echo "FAIL: the page still promises '$g',"
        echo "      and the handler that would do it is inside #if 0."
        rc=1
    fi
done <<< "$GONE"

while IFS= read -r w; do
    [ -n "$w" ] || continue
    if ! printf '%s' "$page" | grep -qF "$w"; then
        echo "FAIL: the page does not say '$w'."
        rc=1
    fi
done <<< "$WANT"

if [ "$rc" = 0 ]; then
    echo "  ok: the Ring of Item Preservation's page promises no transport of"
    echo "      the wearer's items on death, and says what the ring does do."
    echo "      page: $(printf '%s' "$page" | sed 's/.*Item Preservation: //; s/ *Description: .*//')"
    echo "      read off $used"
fi
exit $rc
