#!/bin/bash
# Regression check for the OPT_NATURAL_SPEED floor.
#
# The rule: a creature that can hold a weapon cannot attack faster by adding the
# mass of that weapon to its limb, so its unarmed and natural attacks are never
# slower than the fastest weapon it could hold instead. Incursion gives every
# weapon a speed rating in the data and gives unarmed attacks none, so before
# this switch existed a monk punched at 100% while the nunchaku in his pack
# struck at 160%, and a lizardfolk's claws were slower than a dagger.
#
# This is a deliberate balance change, not a fix to a defect. It is therefore
# NOT marked upstream:, and it is off unless the player turns it on.
#
# The check plays the same character twice from the same seed and the same key
# script, changing one byte of Options.Dat between the runs, and reads the
# Brawl speed off the character sheet. src/Sheet.cpp:151 builds that row from
# KAttr[A_SPD_BRAWL], which is the value src/Values.cpp clamps, so the sheet is
# a true oracle for the code under test. Numbers on both sides, one variable.
#
# Usage: tools/check_natural_speed_live.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/monk-brawl-speed.keys
OPT_BYTE=121          # OPT_NATURAL_SPEED, see inc/Defines.h
WANT_ORIGINAL=100     # unfloored: the class trickle only, and at level 1 it is 0
WANT_FLOORED=175      # NATURAL_SPD_FLOOR 15, displayed as 100 + 15*5

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}
[ -f Options.Dat ] || { echo "FAIL: no Options.Dat to base the two runs on"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Two options files that differ in exactly one byte.
python3 - "$TMP" "$OPT_BYTE" <<'PY' || exit 1
import sys, io
tmp, idx = sys.argv[1], int(sys.argv[2])
b = bytearray(io.open('Options.Dat','rb').read())
if len(b) <= idx:
    raise SystemExit("Options.Dat is %d bytes, too short for option %d" % (len(b), idx))
b[idx] = 0; io.open(tmp + '/original.Dat','wb').write(bytes(b))
b[idx] = 1; io.open(tmp + '/floored.Dat','wb').write(bytes(b))
PY

# Play one session and print the Brawl speed percentage it reported.
brawl_speed() {
    local opts="$1" out run sheet
    out="$(INCURSION_OPTIONS="$opts" tools/headless.sh "$KEYS" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"

    # A session that measured nothing must never read as a pass: that mistake
    # is inc-loa.3. The sheet is only reachable from inside a map.
    if echo "$out" | grep -q "NO GAMEPLAY"; then
        echo "ERR: the run never entered a map" >&2
        return 1
    fi
    sheet="$run/logs/screens/0002-sheet1.txt"
    if [ ! -f "$sheet" ]; then
        echo "ERR: no character sheet dump at $sheet" >&2
        return 1
    fi
    # The Brawl block is three lines; Melee has a Speed line too, so anchor on
    # the Brawl heading and take the Speed line that follows it.
    awk '/^ Brawl /{f=1} f && /Speed/{print; exit}' "$sheet" \
        | grep -o '[0-9][0-9]*%' | head -1 | tr -d '%'
}

echo "--- ORIGINAL (switch off) ---"
got_orig="$(brawl_speed "$TMP/original.Dat")" || exit 1
echo "--- FLOORED (switch on) ---"
got_floor="$(brawl_speed "$TMP/floored.Dat")" || exit 1

echo
echo "brawl speed, switch off: ${got_orig:-<none>}%"
echo "brawl speed, switch on:  ${got_floor:-<none>}%"

fail=0
if [ "${got_orig:-}" != "$WANT_ORIGINAL" ]; then
    echo "FAIL: with the switch off, brawl speed should be ${WANT_ORIGINAL}%"
    fail=1
fi
if [ "${got_floor:-}" != "$WANT_FLOORED" ]; then
    echo "FAIL: with the switch on, brawl speed should be ${WANT_FLOORED}%"
    echo "      If lib/weapons.irh gained a faster weapon, tools/check_natural_speed.sh"
    echo "      says so and WANT_FLOORED here must move with NATURAL_SPD_FLOOR."
    fail=1
fi
if [ "${got_orig:-}" = "${got_floor:-}" ]; then
    echo "FAIL: the switch changed nothing, so this run proved nothing"
    fail=1
fi

[ "$fail" -eq 0 ] && echo && echo "PASS: the switch moves brawl speed from ${got_orig}% to ${got_floor}%."
exit "$fail"
