#!/bin/bash
# Does the Luckblade keep its magical plus when the wish it charges for is not
# delivered? Finding PA-08-F10 of bd inc-tek.8.8.
#
# THE DEFECT. The Luckblade's activation handler (lib/m_items.irh) took the
# payment and then refused the service, in this order: it spent one Plus with
# SetInherentPlus(GetInherentPlus()-1), then reached a wish redirect that its
# own author had commented out, then printed "Wishes aren't implemented yet;
# sorry." The sword starts at INITIAL_PLUS +3, so three presses of the Activate
# command ground a +3 keen short sword down to +0, and the sword's own page
# says that loss "cannot be restored in any manner". Brian's ruling: refuse
# before charging. The refusal now happens first, and the author's original
# code is left below it, unreachable, for whoever implements wish (bd
# inc-tek.30).
#
# THE ORACLE is the Activate command's own menu -- the screen a player reads
# before choosing what to activate. Item::xName writes the plus straight onto
# the item's name for any known item (src/Message.cpp:1300-1308), so the menu
# row says "mildly damaged keen Luckblade +3" in the game's own words, and
# says "mildly damaged keen Luckblade" with no plus at all once the sword is
# drained, because xName writes nothing when GetPlus() is zero. The check
# activates the sword three times and reads that row four times: once before
# and once after each press.
#
# WHY NOT THE LUC SCORE ON THE SIDEBAR. The sword grants its plus as a bonus
# to Luck, so the sidebar looked like a second reading of the same number. It
# is not one. Measured on the pre-fix binary, seed 1: the sidebar went LUC 18,
# 17, 17, 17 while the sword went +3, +2, +1, +0. The handler's own comment
# calls its stati update an "awkward kludge", and the kludge only takes the
# first time. A check reading LUC would have seen two of the three payments
# not happen and could have called the third a rounding difference. The item's
# name is what the item actually is.
#
# WHY THE MESSAGE MUST BE PRESENT. A run in which the activation never fired
# would show a stable plus for the wrong reason and prove nothing at all. So
# the refusal message is required on all three message dumps; without it this
# reports INCONCLUSIVE and exits 2, never a pass.
#
# Usage: tools/check_luckblade_plus.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
WANT=3          # INITIAL_PLUS, and the plus the sword's page states

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/luckblade-plus.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script could not find something on screen. Run: $run"
    exit 2
fi

scr="$run/logs/screens"
for n in 1 2 3 4; do
    [ -f "$scr/000$((n*2))-menu-$n.txt" ] || {
        echo "INCONCLUSIVE: no screen dumped at $scr/000$((n*2))-menu-$n.txt"
        exit 2
    }
done
for n in 1 2 3; do
    [ -f "$scr/000$((n*2+1))-msg-$n.txt" ] || {
        echo "INCONCLUSIVE: no screen dumped at $scr/000$((n*2+1))-msg-$n.txt"
        exit 2
    }
done

# The key script chooses the menu's first entry by its letter, so read that
# entry's text back before believing anything. A menu that had gained a second
# activatable item would otherwise activate the neighbour in silence. The row
# is the one carrying "[a]" inside the menu box.
menu_row() { # <screen dump> -> the text of the [a] entry
    grep -o '\[a\][^|]*' "$1" | head -1 | sed 's/  *$//'
}

# The plus as the game wrote it. An absent plus is +0: Item::xName appends
# nothing at all when GetPlus() is zero (src/Message.cpp:1300).
plus_of() { # <menu row> -> the number
    case "$1" in
        *"Luckblade +"*) echo "${1##*Luckblade +}" ;;
        *)               echo 0 ;;
    esac
}

for n in 1 2 3 4; do
    eval "ROW$n=\"\$(menu_row "$scr/000$((n*2))-menu-$n.txt")\""
    eval "row=\$ROW$n"
    case "$row" in
        *Luckblade*) ;;
        *) echo "INCONCLUSIVE: menu $n does not offer a Luckblade, so the"
           echo "              session activated the wrong item or none."
           echo "              Row: ${row:-<no [a] entry on screen>}"
           echo "              Screen: $scr/000$((n*2))-menu-$n.txt"
           exit 2 ;;
    esac
done

# Did the sword ever actually get activated? This is the guard that stops a
# stable plus being read as a pass when nothing happened at all.
for n in 1 2 3; do
    f="$scr/000$((n*2+1))-msg-$n.txt"
    grep -q "Wishes aren't implemented yet" "$f" || {
        echo "INCONCLUSIVE: activation $n printed no refusal, so the sword was"
        echo "              never activated and this session measured nothing."
        echo "              Screen: $f"
        exit 2
    }
done

START="$(plus_of "$ROW1")"
if [ "$START" != "$WANT" ]; then
    echo "INCONCLUSIVE: the sword did not start at +$WANT but at +$START, so"
    echo "              there is no known quantity to compare against."
    echo "              Row: $ROW1"
    exit 2
fi

rc=0
for n in 2 3 4; do
    eval "row=\$ROW$n"
    got="$(plus_of "$row")"
    if [ "$got" != "$WANT" ]; then
        echo "FAIL: after $((n-1)) activation(s) that granted no wish, the sword is"
        echo "      +$got. It was +$WANT, and its page says the loss cannot be"
        echo "      restored in any manner."
        echo "      Row: $row"
        rc=1
    fi
done

if [ "$rc" = 0 ]; then
    echo "  ok: three activations, three refusals, and the sword keeps its plus"
    echo "      before:  $ROW1"
    echo "      after 3: $ROW4"
    echo "      said:    $(grep -oh "Wishes aren't implemented yet; sorry." "$scr/0003-msg-1.txt")"
fi
exit $rc
