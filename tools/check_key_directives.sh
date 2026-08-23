#!/bin/bash
# Regression check for the screen-driven key-script directives, bd inc-cso:
# @choose, @cursorto, @cursorto:mark and @expect.
#
# WHAT IS BEING PROVED. Before these existed, a key script reached a menu entry
# by counting -- "i" for Rogue, "DOWN*9" for the Loremaster -- and the count was
# a position in a list built from lib/. Adding one race, class or prestige class
# moved every position after it, and the script then drove a different character
# and still finished, still exited 0, and still produced a plausible run. Three
# of the four assertions below are therefore not "the directive worked" but "the
# directive reached somewhere counting could not have reached".
#
# Usage: tools/check_key_directives.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
fail=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

say_fail() { echo "FAIL: $1"; fail=1; }

# ---------------------------------------------------------------------------
# 1. @cursorto:mark reaches a skill by name in the Skill Manager.
#
# The Skill Manager has no menu letters: it is a scrolling list with a '>'
# beside the current row. tools/keys/skill-by-name.keys names nine skills that
# all sit LATE in the list. Counting down from the top -- which is what
# tools/keys/chargen-rogue.keys does -- fills the first nine instead, Alchemy
# through Diplomacy. So "Alchemy has no ranks" is the half of this assertion
# that counting cannot fake.
echo "-- @cursorto:mark: spending ranks by name"
OUT="$(tools/headless.sh tools/keys/skill-by-name.keys "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SHEET="$RUN/logs/sheet.txt"

if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    say_fail "the run never entered a map, so it measured nothing"
elif [ ! -f "$SHEET" ]; then
    say_fail "the sheet was never written to $SHEET"
else
    for skill in Listen Lockpicking "Move Silently" Perform "Pick Pockets" \
                 "Poison Use" Ride Spot Tumble; do
        line="$(grep -m1 "^  $skill  *+" "$SHEET")"
        if echo "$line" | grep -q "(2 ranks"; then
            echo "  ok: $line"
        else
            say_fail "$skill was named but holds no ranks"
            [ -n "$line" ] && echo "      $line"
        fi
    done
    # The discriminating half: these two are where counting would have put them.
    for skill in Alchemy Appraise; do
        line="$(grep -m1 "^  $skill  *+" "$SHEET")"
        if echo "$line" | grep -q "(0 ranks"; then
            echo "  ok: $line"
        else
            say_fail "$skill holds ranks, so the ranks were spent by position"
            [ -n "$line" ] && echo "      $line"
        fi
    done
fi

# ---------------------------------------------------------------------------
# 2. RETIRED -- @cursorto matches a name the menu has truncated.
#
# LMenu cuts every entry to its column width (src/TextTerm.cpp:1403 cuts the
# stored text, :1462 prints one character less), so the prestige list drew
# "[e] Celestial Initiat" and the full name appeared nowhere on the screen.
# That was the specimen: a directive that could not match it would be useless
# on any long name.
#
# Celestial Initiate is one of the eight unfinished prestige classes. They now
# carry CF_PSEUDO and appear in no list, and no remaining prestige class name
# is long enough to truncate -- "Twilight Huntsman" and "Underdark Warrior" are
# 17 characters and fit exactly. This check is therefore short one assertion
# until a replacement menu is found. See bd inc-m09m; it names the candidates
# already probed and rejected.

# ---------------------------------------------------------------------------
# 3. A directive that cannot find its target stops the run.
#
# This is the point of the whole feature. A script that misses its target and
# carries on produces a plausible run of the wrong character, and every caller
# that reads the exit code counts it as a pass -- the trap of inc-loa.3. All
# three of these must end 6, EXIT_SCRIPT_FAILED.
echo "-- failing closed"
printf 'a\nn\ny\n@expect "Choose a hat"\n'          > "$TMP/no-such-text.keys"
printf 'a\nn\ny\n@choose "Gelatinous Cube"\n'       > "$TMP/no-such-entry.keys"
printf 'a\nn\ny\n@choose "Elf"\n@choose "Elf (Standard)"\n@choose "Ba"\n' \
                                                    > "$TMP/two-entries.keys"

for t in no-such-text no-such-entry two-entries; do
    tools/headless.sh "$TMP/$t.keys" "$SEED" >/dev/null 2>"$TMP/$t.err"
    rc=$?
    if [ "$rc" = 6 ]; then
        echo "  ok: $t ended 6 -- $(grep -m1 -o 'incursion: .*failed' "$TMP/$t.err")"
    else
        say_fail "$t ended $rc; a directive that finds nothing must end 6"
    fi
done

# ---------------------------------------------------------------------------
# 4. @choose picks the entry that matches outright, not the first that starts
#    the same way. The alignment screen offers "[b] Neutral Good", "[e] Neutral"
#    and "[h] Neutral Evil", and every script in tools/keys asks for the middle
#    one. Both runs above chose it; the sheet is where it shows.
echo "-- @choose: an exact name beats a longer one that starts the same way"
if [ -f "$SHEET" ] && grep -q "Align  Neutral *$" "$SHEET"; then
    echo "  ok: $(grep -m1 'Align ' "$SHEET")"
elif [ -f "$SHEET" ]; then
    say_fail "@choose \"Neutral\" did not select [e] Neutral"
    grep -m1 "Align " "$SHEET"
fi

if [ "$fail" = 0 ]; then
    echo "PASS: @choose, @cursorto, @cursorto:mark and @expect each drive by name"
    exit 0
fi
exit 1
