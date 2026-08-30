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
# the Look row must read "D-pad Right (l)"; without it the dump must not
# mention the d-pad at all. So a pass proves both the hint and the gate. The
# override, not a real pad, is what the headless build can exercise; the
# vendor-id and SteamGameId detection in libtcodTerm::PadAttached
# (src/Wlibtcod.cpp) is verified on the device, not here.
#
# Measured red-before / green-after on 2026-08-30, seed 7.
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
    if ! echo "$out" | grep -q "^ended: *cleanly"; then
        echo "INCONCLUSIVE ($1): the session did not finish, so it says nothing" >&2
        echo "              about the ? screen. The chargen questions have" >&2
        echo "              probably moved; fix $KEYS first." >&2
        echo "$out" | sed -n '/--- after the session ---/,$p' >&2
        return 2
    fi
    local dump="$run/logs/screens/0001-help.txt"
    [ -f "$dump" ] || { echo "INCONCLUSIVE ($1): no help dump at $dump" >&2; return 2; }
    echo "$dump"
}

PAD="$(one_run pad INCURSION_PAD_HELP=1)" || exit 2
KBD="$(one_run keyboard INCURSION_PAD_HELP=)" || exit 2

# The assertion: with the override on, Look carries its pad control.
if ! grep -q "Look .*D-pad Right (l)" "$PAD"; then
    echo "FAIL: with INCURSION_PAD_HELP=1 the ? screen does not read"
    echo "      'Look ... D-pad Right (l)'. DescribeKeys (src/Help.cpp) must"
    echo "      print the PadHints entry. Dump: $PAD"
    exit 1
fi

# The control: with the override off, no pad control appears anywhere.
if grep -q "D-pad" "$KBD"; then
    echo "FAIL: without INCURSION_PAD_HELP the ? screen still names the d-pad,"
    echo "      so the keyboard-only screen is gone. Dump: $KBD"
    exit 1
fi

echo "PASS: the ? screen reads 'D-pad Right (l)' beside Look with"
echo "      INCURSION_PAD_HELP=1 and names no pad control without it."
exit 0
