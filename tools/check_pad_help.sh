#!/bin/bash
# Regression check: the ? screen names the pad control beside each key when a
# controller is in front of the game, and stays keyboard-only when none is.
#
# WHY IT EXISTS. On the Ally the d-pad and buttons reach the game as the
# keystrokes Steam Input synthesises, so a player who presses ? sees "l" and
# no hint that D-pad Right is Look. DescribeKeys (src/Help.cpp) now prints the
# pad control from the PadHints table when Term::PadHelpActive() is true, which
# the INCURSION_PAD_HELP environment variable forces for this check.
#
# HOW IT PROVES IT. tools/keys/pad-help.keys builds a character, presses ? in
# play and dumps the screen. The check runs it twice: with INCURSION_PAD_HELP=1
# the Look row must read "D-pad > (l)" (the arrow glyph dumps as ">") and the
# title must be on screen; without it the dump must not mention the d-pad at
# all. Either run ending in anything but "cleanly" is a FAIL, not an
# INCONCLUSIVE: the first version of this check called the 2026-08-30 crash
# inconclusive and passed, while headless.sh had logged the very assert
# (exit 7 now). The override, not a real pad, is what the headless build can
# exercise; the vendor-id and SteamGameId detection in
# libtcodTerm::PadAttached (src/Wlibtcod.cpp) is verified on the device.
#
# Measured red-before / green-after on 2026-08-30, seed 7, both for the
# missing hint (first version) and for the one-column overflow (this one).
#
# Usage: tools/check_pad_help.sh [seed]
# Ends:  0 pass, 1 fail, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${1:-7}"
KEYS="tools/keys/pad-help.keys"
BIN="${INCURSION_BIN:-./incursion-headless}"

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: no key script at $KEYS"; exit 2; }

# one_run <label> <env-setting>: run the script, print the path of the help dump.
one_run() {
    local out run
    out="$(env $2 INCURSION_BIN="$BIN" tools/headless.sh "$KEYS" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q "^ended: *ASSERT"; then
        echo "FAIL ($1): the engine tripped an assertion opening the ? screen." >&2
        echo "      On 2026-08-30 that was the one-column list overflowing the" >&2
        echo "      screen (SizeWin, src/TextTerm.cpp)." >&2
        echo "$out" | grep -A3 "^ended:" >&2
        return 1
    fi
    if ! echo "$out" | grep -q "^ended: *cleanly"; then
        echo "FAIL ($1): the session did not end cleanly, so the ? screen was" >&2
        echo "      not shown as scripted. If the chargen questions moved, fix" >&2
        echo "      $KEYS; otherwise the screen itself is at fault." >&2
        echo "$out" | sed -n '/--- after the session ---/,$p' >&2
        return 1
    fi
    local dump="$run/logs/screens/0001-help.txt"
    [ -f "$dump" ] || { echo "INCONCLUSIVE ($1): no help dump at $dump" >&2; return 2; }
    echo "$dump"
}

PAD="$(one_run pad INCURSION_PAD_HELP=1)" || exit $?
KBD="$(one_run keyboard INCURSION_PAD_HELP=)" || exit $?

# The assertion: with the override on, Look carries its pad control.
if ! grep -q "Look .*D-pad > (l)" "$PAD"; then
    echo "FAIL: with INCURSION_PAD_HELP=1 the ? screen does not read"
    echo "      'Look ... D-pad > (l)'. DescribeKeys (src/Help.cpp) must"
    echo "      print the PadHints entry. Dump: $PAD"
    exit 1
fi

# The whole screen must be on screen: the title is its first line, and a
# list taller than the box scrolls it off the top (seen 2026-08-30).
if ! grep -q "Incursion Key Bindings (controller)" "$PAD"; then
    echo "FAIL: the controller ? screen's title is not on screen, so the list"
    echo "      overflowed its box and scrolled. Dump: $PAD"
    exit 1
fi

# The order: the Direction Keys header is the first list row, alone on its
# row, and North is the first entry under it. On 298ce72 the list went
# through a boolean qsort comparator and came out with "Rest and Recover"
# first and that header at the bottom of the right column (inc-pk2p).
if ! grep -A1 "Incursion Key Bindings (controller)" "$PAD" | tail -1 | grep -q "^| *Direction Keys *|$"; then
    echo "FAIL: the row under the title is not the Direction Keys header on"
    echo "      its own, so the list is out of order or the headers share"
    echo "      rows with entries (inc-pk2p). Dump: $PAD"
    exit 1
fi
if ! grep -A2 "Incursion Key Bindings (controller)" "$PAD" | tail -1 | grep -q "^| *North "; then
    echo "FAIL: North is not the first entry under Direction Keys (inc-pk2p)."
    echo "      Dump: $PAD"
    exit 1
fi

# The control: with the override off, no pad control appears anywhere.
if grep -q "D-pad" "$KBD"; then
    echo "FAIL: without INCURSION_PAD_HELP the ? screen still names the d-pad,"
    echo "      so the keyboard-only screen is gone. Dump: $KBD"
    exit 1
fi

echo "PASS: the ? screen reads 'D-pad > (l)' beside Look, opens with the"
echo "      Direction Keys header then North, fits with no assertion, under"
echo "      INCURSION_PAD_HELP=1; it names no pad control without it."
exit 0
