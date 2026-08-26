#!/bin/bash
# Regression check for inc-upw.52: AutoPickupFloor's unidentified-magic branch
# (src/Player.cpp) must not auto-stow a grantless holy symbol -- or the shield a
# priest drops stamped with the same god emblem -- while it still stows real
# unidentified magic. Item::isFlavorGodMark() excludes the emblems; this proves
# the exclusion holds without silencing the branch.
#
# WHAT IT ASSERTS, from the two screen dumps tools/keys/symbol-autopickup.keys
# writes on seed 1. It reads the "Things in View" panel, not the one-line
# message window, so it is robust to message wrapping:
#   SETUP  before the pickup settles, the dead priest's ? holy symbol is on the
#          player's tile (else INCONCLUSIVE -- a dead session proves nothing)
#   RAN    the branch ran: the unidentified potions are gone from view (stowed)
#   A      the ? holy symbol is STILL in view after the pickup -- not stowed
#   B      the god-marked buckler is STILL in view after the pickup -- not stowed
#
# A and B are red on the build before the fix, where both are stowed and leave
# the view. The potions stow in both builds, so RAN holds either way.
#
# Usage: tools/check_symbol_autopickup.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/symbol-autopickup.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
before="$(ls "$run"/logs/screens/*before* 2>/dev/null | head -1)"
after="$(ls "$run"/logs/screens/*after*  2>/dev/null | head -1)"

[ -f "$before" ] && [ -f "$after" ] || {
    echo "INCONCLUSIVE: the session wrote no before/after dump. Run dir: $run"
    exit 2
}

# The right-hand "Things in View" list, from its header down to the HP line.
view() { sed -n '/Things in View/,/HP:/p' "$1"; }

# SETUP: the symbol reached the tile before the pickup settled.
grep -qi "holy symbol" "$before" || {
    echo "INCONCLUSIVE: no ? holy symbol on the tile before pickup -- the summon or"
    echo "              priest template dropped none. Run dir: $run"
    exit 2
}

# RAN: the branch fired -- the unidentified potions left the view (were stowed).
if view "$after" | grep -qi "potion"; then
    echo "INCONCLUSIVE: potions still in view after pickup, so the unidentified-magic"
    echo "              branch never ran on this tile. Run dir: $run"
    exit 2
fi

fail=0
if ! view "$after" | grep -qi "holy symbol"; then
    echo "FAIL: the holy symbol left the view after pickup -- it was auto-stowed."
    fail=1
fi
if ! view "$after" | grep -qi "orcish"; then
    echo "FAIL: the god-marked buckler left the view after pickup -- it was auto-stowed."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: the holy symbol and the god-marked buckler stayed in view; the"
    echo "      unidentified potions were stowed. run: $run"
    exit 0
fi
echo "      run: $run"
exit 1
