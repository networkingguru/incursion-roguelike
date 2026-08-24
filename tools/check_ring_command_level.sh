#!/bin/bash
# Do the Rings of Elemental Command grant the command power their own pages
# promise? Finding PA-08-F4 of bd inc-tek.8.8.
#
# THE DEFECT. Each of the four rings prints, on its own page, that it lets the
# wearer "command <element> creatures as an <Element> priest of 12th level, or
# augments their existing ability by +6 -- whichever is superior"
# (lib/m_items.irh:4459, :4532, :4606, :4699). All four then handed out
#
#   max(10,clev+5)
#
# which is 10th level and +5. The page is what the player reads, so the page
# wins: the four sites now say max(12,clev+6).
#
# THE ORACLE is wizard mode's "Examine Player Data", which prints every stati
# with its Val and its Mag (src/Debug.cpp:1528-1584). Val names the element --
# MA_WATER 92, MA_AIR 93, MA_EARTH 94, MA_FIRE 95 (inc/Defines.h:1610-1613) --
# and Mag is the granted level itself. The scripted character is 1st level, so
# max(10,clev+5) reads 10 and max(12,clev+6) reads 12.
#
# It has to be this and not behaviour. The number is a check bonus, not a
# hit-dice cap: src/Skills.cpp:2162 reads it, and :4448-4562 adds a d20, a
# feat, a Knowledge rank and Charisma before dividing by resistance. Two extra
# points shift a probability and cross no threshold, so a behavioural test
# would need thousands of trials to see what one screen states outright.
#
# Usage: tools/check_ring_command_level.sh     (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
WANT=12

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/ring-command-level.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script could not find something on screen. Run: $run"
    exit 2
fi

worn1="$run/logs/screens/0001-rings-on.txt"
stati1="$run/logs/screens/0002-stati.txt"
worn2="$run/logs/screens/0003-rings-on2.txt"
stati2="$run/logs/screens/0004-stati2.txt"
for f in "$worn1" "$stati1" "$worn2" "$stati2"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: no screen dumped at $f"; exit 2; }
done

# The acquisition list is walked by cursor and not by menu letter, so read
# every ring's name back off the inventory screen before believing any number
# the debug dump prints. A cursor that stopped one row early would otherwise
# measure a different ring and still pass.
ring_on() { # <screen> <slot> <element>
    grep -qF "$2:Ring of Elemental Command ($3)" "$1" || {
        echo "INCONCLUSIVE: no Ring of Elemental Command ($3) on the $2 slot,"
        echo "              so the session measured the wrong item or none."
        echo "              Screen: $1"
        exit 2
    }
}
ring_on "$worn1" "Left Ring    " "Water"
ring_on "$worn1" "Right Ring   " "Fire"
ring_on "$worn2" "Left Ring    " "Air"
ring_on "$worn2" "Right Ring   " "Earth"

rc=0
level_of() { # <screen> <MA_ value> <element>
    local line mag
    line="$(grep -o "COMMAND ABILITY from SS ITEM (Val:$2 Mag:[0-9]*)" "$1" | head -1)"
    if [ -z "$line" ]; then
        echo "INCONCLUSIVE: the $3 ring granted no command ability at all"
        echo "              (no stati with Val:$2). Screen: $1"
        exit 2
    fi
    mag="${line##*Mag:}"
    mag="${mag%)}"
    if [ "$mag" != "$WANT" ]; then
        echo "FAIL: the $3 ring commands as a priest of level $mag, but its"
        echo "      page promises $WANT. $line"
        echo "      Screen: $1"
        rc=1
    fi
}
level_of "$stati1" 92 "Water"
level_of "$stati1" 95 "Fire"
level_of "$stati2" 93 "Air"
level_of "$stati2" 94 "Earth"

[ "$rc" = 0 ] && echo "  ok: all four elemental command rings grant level $WANT, as their pages say"
exit $rc
