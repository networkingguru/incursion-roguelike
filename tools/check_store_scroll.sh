#!/bin/bash
# Regression check for the shop list that would not scroll, inc-upw.23.
#
# TextTerm::BarterManager (src/Managers.cpp:1091) draws its own list and keeps
# its own selection. Every arrow key jumped back to its PartialRedraw label,
# which begins with ClearScroll(true) -- and ClearScroll(true) zeroes
# TextTerm::offset (src/TextTerm.cpp:720-728). The single UpdateScrollArea call
# at the end of the redraw therefore always drew row 0 at the top of the page,
# whatever the NORTH and SOUTH cases had just worked out. The selection walked
# off the page and stayed off it. Both directions were dead, not just one; the
# beads issue's first diagnosis blamed a hardcoded 32 and predicted that UP
# still worked, and Brian falsified that from play on 2026-08-19.
#
# The run visits Roark Ironbeard's store, which is reached without wizard mode:
# the cave entrance asks "Store, Inn, Retire or Descend?" (lib/dungeon.irh:203)
# and [s] throws EV_BARTER at a shopkeeper carrying 40-odd stacks.
#
# Measured 2026-08-19, seed 1, same key script, src/Managers.cpp the only
# file different between the two builds:
#
#   after DOWN*40   before: page still starts "00) coil of a hemp rope",
#                           byte-identical to the opening screen
#                   after:  page starts "06) an alchemy set", up-arrow shown
#   after UP*40     before: unchanged (it never left row 0)
#                   after:  back to "00) coil of a hemp rope"
#
# THE RUN CAN FAIL TO MEASURE ANYTHING, and that is reported as INCONCLUSIVE
# rather than FAIL: a session that never reached the shop, or whose DOWN keys
# never reached the menu, says nothing about the bug. Sending somebody hunting
# a regression that a dead session invented is the mistake of inc-loa.3.
#
# Usage: tools/check_store_scroll.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
ROW0="00) coil of a hemp rope"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/store-scroll.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
S="$run/logs/screens"

for f in 0001-store-open 0002-examine-top 0003-store-down 0004-examine-down 0005-store-up; do
    [ -f "$S/$f.txt" ] || {
        echo "INCONCLUSIVE: the session produced no $f screen. Run dir: $run"
        exit 2
    }
done

# Did the shop open at all, and at the top of its list?
grep -q "$ROW0" "$S/0001-store-open.txt" || {
    echo "INCONCLUSIVE: the shop never opened on row 0. Run dir: $run"
    exit 2
}

# Did the DOWN keys reach the menu? Without this the check cannot tell a list
# that refuses to scroll from a session that never pressed anything: both leave
# the page showing row 0. [x] describes the SELECTED row, so two different
# descriptions prove the selection moved.
if diff -q <(tail -n +2 "$S/0002-examine-top.txt") \
           <(tail -n +2 "$S/0004-examine-down.txt") >/dev/null; then
    echo "INCONCLUSIVE: [x] described the same row before and after DOWN*40,"
    echo "              so the selection never moved. Run dir: $run"
    exit 2
fi

fail=0

if grep -q "$ROW0" "$S/0003-store-down.txt"; then
    echo "FAIL: after DOWN*40 the page still starts at row 0 -- it did not scroll."
    fail=1
fi

if ! grep -q "$ROW0" "$S/0005-store-up.txt"; then
    echo "FAIL: after UP*40 the page did not come back to row 0."
    fail=1
fi

if [ "$fail" = 1 ]; then
    echo "Run dir: $run"
    exit 1
fi

echo "PASS: the shop list follows the selection down the page and back up."
echo "Run dir: $run"
exit 0
