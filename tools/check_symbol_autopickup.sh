#!/bin/bash
# Regression check for inc-upw.52: AutoPickupFloor's unidentified-magic branch
# (src/Player.cpp) must not auto-stow a holy symbol a dead priest drops -- of
# ANY god -- while it still stows real unidentified magic. Item::isFlavorGodMark()
# excludes the emblems; this proves the exclusion holds without silencing the
# branch. It reads the "Things in View" panel, not the one-line message window,
# so it is robust to message wrapping.
#
# TWO SEEDS, because a holy symbol comes in two flavours and the fix must exempt
# both. The priest template (lib/mon2.irh) rolls one of 16 gods and stamps the
# symbol AND a shield with it. 15 of those gods define an EA_GENERIC symbol; only
# Hesani's is EA_GRANT (lib/religion.irh). isFlavorGodMark() must exempt the
# symbol whichever it is, while still letting a granting SHIELD hoard as the real
# magic it is.
#
#   SEED 1  -- an EA_GENERIC god. The dropped ? holy symbol AND the god-marked
#              buckler both stay in view; the unidentified potions stow.
#   SEED 38 -- Hesani, the one EA_GRANT god. The ? holy symbol stays, but its
#              granting ? kite shield stows (real magic still hoards), proving the
#              exemption keys on "is a holy-symbol item", not "grants nothing".
#
# The "symbol stays" assertions are red on the build before the fix: seed 1's
# symbol stowed once the old grantless-only rule missed the T_SYMBOL exemption,
# and seed 38's symbol stowed because the old rule dropped every EA_GRANT emblem.
# Confirmed red on the pre-fix binary and green on the rebuilt one.
#
# Usage: tools/check_symbol_autopickup.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# The right-hand "Things in View" list, from its header down to the HP line.
view() { sed -n '/Things in View/,/HP:/p' "$1"; }

# Run the fixture on one seed; set globals BEFORE and AFTER to the two dumps.
run_seed() {
    local seed="$1" out run
    out="$(tools/headless.sh tools/keys/symbol-autopickup.keys "$seed" 2>&1)"
    RUN="$(echo "$out" | awk '/^run:/ {print $2}')"
    BEFORE="$(ls "$RUN"/logs/screens/*before* 2>/dev/null | head -1)"
    AFTER="$(ls "$RUN"/logs/screens/*after*  2>/dev/null | head -1)"
}

fail=0

# --- SEED 1: an EA_GENERIC god. Symbol and god-marked buckler both stay. ---
run_seed 1
[ -f "$BEFORE" ] && [ -f "$AFTER" ] || {
    echo "INCONCLUSIVE: seed 1 wrote no before/after dump. Run dir: $RUN"; exit 2; }
grep -qi "holy symbol" "$BEFORE" || {
    echo "INCONCLUSIVE: seed 1 dropped no ? holy symbol on the tile. Run dir: $RUN"; exit 2; }
if view "$AFTER" | grep -qi "potion"; then
    echo "INCONCLUSIVE: seed 1 potions still in view -- the branch never ran. Run dir: $RUN"; exit 2; fi
if ! view "$AFTER" | grep -qi "holy symbol"; then
    echo "FAIL: seed 1 holy symbol left the view after pickup -- it was auto-stowed."; fail=1; fi
if ! view "$AFTER" | grep -qi "orcish"; then
    echo "FAIL: seed 1 god-marked buckler left the view after pickup -- it was auto-stowed."; fail=1; fi

# --- SEED 38: Hesani (EA_GRANT). Symbol stays; its granting shield hoards. ---
run_seed 38
[ -f "$BEFORE" ] && [ -f "$AFTER" ] || {
    echo "INCONCLUSIVE: seed 38 wrote no before/after dump. Run dir: $RUN"; exit 2; }
grep -qi "holy symbol" "$BEFORE" || {
    echo "INCONCLUSIVE: seed 38 dropped no ? holy symbol on the tile. Run dir: $RUN"; exit 2; }
view "$BEFORE" | grep -qi "kite shield" || {
    echo "INCONCLUSIVE: seed 38 dropped no ? kite shield -- the Hesani priest's roll drifted."; echo "              Run dir: $RUN"; exit 2; }
# RAN + granting shield hoards: the EA_GRANT kite shield must leave the view.
if view "$AFTER" | grep -qi "kite shield"; then
    echo "INCONCLUSIVE: seed 38 kite shield still in view -- the branch never ran, or a"
    echo "              granting shield stopped hoarding. Run dir: $RUN"; exit 2; fi
if ! view "$AFTER" | grep -qi "holy symbol"; then
    echo "FAIL: seed 38 Hesani holy symbol left the view after pickup -- it was auto-stowed."
    echo "      The EA_GRANT emblem is a holy symbol and must stay exempt. run: $RUN"; fail=1; fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: the holy symbol stayed in view on both an EA_GENERIC god (seed 1, its"
    echo "      buckler stayed too) and Hesani (seed 38, its granting shield hoarded)."
    exit 0
fi
exit 1
