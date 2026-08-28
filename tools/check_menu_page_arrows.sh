#!/bin/bash
# Regression check: the RIGHT arrow pages a long selection menu, inc-7h6s.
#
# WHY IT EXISTS. The Steam Deck maps a stick to the arrow keys, so a handheld
# player has Right and Left but not Tab. A paged LMenu (src/TextTerm.cpp) must
# therefore page on Right (forward) and Left (back), the way it pages on Tab and
# Shift-Tab. This check watches the forward half.
#
# HOW IT PROVES IT. tools/keys/menu-page-right.keys builds the same Wood Elf
# Druid that tools/keys/menu-overflow.keys builds -- 88 feats, a three-column
# menu that pages. Natural Aptitude is the 61st feat, off the first page. The
# script turns the page with RIGHT, never Tab, then @choose reads the letter the
# game printed beside the name and presses it. On a build without inc-7h6s,
# RIGHT does the old within-page column move and never crosses a page boundary,
# so the name never appears, @choose refuses, and the run ends with exit 6. So a
# pass proves RIGHT paged forward AND the paged row was still selectable.
#
# This is the arrow-key sibling of tools/check_menu_overflow.sh, which drives
# the identical menu with Tab. Measured red-before / green-after on 2026-08-28,
# seed 7, src/TextTerm.cpp the only file that changed.
#
# Usage: tools/check_menu_page_arrows.sh [seed]
# Ends:  0 pass, 1 fail, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${1:-7}"
KEYS="tools/keys/menu-page-right.keys"
BIN="${INCURSION_BIN:-./incursion-headless}"
WANT="Natural Aptitude"

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: no key script at $KEYS"; exit 2; }

OUT="$(INCURSION_BIN="$BIN" tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCREENS="$RUN/logs/screens"

# The failure the missing fix produces: RIGHT never turned the page, so the
# name the script paged toward was never on screen and @choose could not read a
# letter for it. Named exactly so a different stall is not misreported as this.
if echo "$OUT" | grep -q "no entry with that name is on screen"; then
    echo "FAIL: RIGHT did not page the feat menu forward, so '$WANT' never"
    echo "      appeared and could not be chosen. The KY_CMD_EAST case in"
    echo "      LMenu (src/TextTerm.cpp) must turn the page at the right edge."
    echo "      inc-7h6s. Screens: $SCREENS"
    exit 1
fi

if echo "$OUT" | grep -qE "^ended:.*(never showed|key budget|watchdog)"; then
    echo "INCONCLUSIVE: the session did not finish, so it says nothing about"
    echo "              paging. The chargen questions have probably moved;"
    echo "              fix $KEYS first."
    echo "$OUT" | sed -n '/--- after the session ---/,$p'
    exit 2
fi

if [ ! -d "$SCREENS" ]; then
    echo "INCONCLUSIVE: no screen dumps at $SCREENS"
    exit 2
fi

# The control: a run whose druid never reached the dungeon measured nothing.
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: the run never entered a map, so it measured nothing."
    echo "              Screens: $SCREENS"
    exit 2
fi

# The assertion: the feat reached only by paging is on the finished character.
if grep -qh "$WANT" "$SCREENS"/*.txt; then
    echo "PASS: a Wood Elf Druid paged the 88-feat menu with the RIGHT arrow,"
    echo "      took Natural Aptitude off a later page, and carries it on his"
    echo "      character sheet. inc-7h6s."
    exit 0
fi

echo "FAIL: the run finished but no screen shows '$WANT'."
echo "      RIGHT paged wrong, or the feat did not stick. Screens: $SCREENS"
exit 1
