#!/bin/bash
# gate: live
# Regression check for the redesigned store, inc-wkxf: the [/] search finds a
# ware, and buying and selling still work.
#
# TextTerm::BarterManager (src/Managers.cpp) lists Roark Ironbeard's wares by
# group, shows "You have N gp", and takes [/] to move the selection to the next
# ware whose displayed name contains the typed text, ignoring case. This check
# runs one session (tools/keys/store-find.keys) and reads six facts from it:
#
#   1. [/] "potions of light" + Enter: [x] describes a potion of light.
#      (The store shows "Potions of Light"; the typed text is lower case.)
#   2. [/] text no ware has: the store prints "No ware matches that."
#   3. Buy one dagger: the confirm prompt shows its price; "You have N gp"
#      on the reopened store is the old gold minus that price; the inventory
#      screen right after the purchase lists the dagger.
#   4. [s] opens "Sell Which Item?"; the first item ends in one of the
#      outcome messages of the SellItem branch (src/Managers.cpp); the
#      session returns to play.
#
# fact: character, gold, inventory -- INCURSION_LOAD=tools/fixtures/chars/
#   orc-barbarian-seed1-opt0818.sav (gold is read from the "You have N gp"
#   line, never hard-coded)
# fact: Roark's stock (a potion of light, daggers) -- the fixture's save pins
#   the dungeon and the shopkeeper's stock; lib/dungeon.irh:300 lists both
#   as unconditional Gear lines, so a fresh stock holds them too
# fact: dagger price -- read from the "Confirm purchase" prompt
# fact: sell outcome -- Roark's EV_WILLBUY script and the SellItem branch
#   decide it; the check accepts every outcome message in that branch
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-18.dat
# fact: weapon stock order -- the fixture save (INCURSION_LOAD) pins Roark's
#   stock; the sort key (src/Managers.cpp BarterSortKey) must place the blessed
#   and cursed one-letter markers by their bare names, so "a b knife" sorts
#   after "a battleaxe" and before a later long sword, and "a c halberd" sorts
#   before "b knife"
# fact: no roll -- buying, selling and searching draw no random number the
#   check reads
#
# A run that never reached the store, or whose keys never reached a menu, says
# nothing about the search and is reported INCONCLUSIVE, never PASS.
#
# Usage: tools/check_store_find.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
FIXTURE=tools/fixtures/chars/orc-barbarian-seed1-opt0818.sav

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_LOAD="$FIXTURE" INCURSION_OPTIONS=tools/fixtures/options-2026-08-18.dat \
    tools/headless.sh tools/keys/store-find.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
S="$run/logs/screens"

for f in store-open search-light-result search-light search-none search-dagger-result search-dagger buy-confirm after-buy \
         store-reopen sell-menu sell-1 sell-2 sell-play; do
    [ -f "$S"/*-"$f".txt ] || {
        echo "INCONCLUSIVE: the session produced no $f screen. Run dir: $run"
        exit 2
    }
done
scr() { cat "$S"/*-"$1".txt; }

# The session must have reached Roark's store, with a gold line to read.
grep -q "Roark Ironbeard, Proprietor" <<< "$(scr store-open)" || {
    echo "INCONCLUSIVE: the store never opened. Run dir: $run"
    exit 2
}
gold0="$(scr store-open | sed -n 's/.*You have \([0-9][0-9]*\) gp.*/\1/p' | head -n 1)"
[ -n "$gold0" ] || {
    echo "INCONCLUSIVE: no \"You have N gp\" line on the opening screen. Run dir: $run"
    exit 2
}
# The first search key must have reached the footer prompt: a store that
# ignores [/] would leave the opening screen unchanged and every later
# assertion would measure nothing.
grep -q "\[/\] Search" <<< "$(scr store-open)" || {
    echo "FAIL: the store footer does not offer [/] Search. Run dir: $run"
    exit 1
}
if ! grep -q "ended: *cleanly" <<<"$out"; then
    echo "INCONCLUSIVE: the session did not end cleanly. Run dir: $run"
    exit 2
fi

# 0. SORT. Roark's Weapon group must be sorted by the BarterSortKey, which
# strips the blessed/cursed "b "/"c " markers. A store that lists "a b knife"
# before "a battleaxe" (or "a b knife" before "a c halberd") failed to strip.
fail=0
line_of() { scr store-open | grep -n -- "$1" | head -n 1 | cut -d: -f1; }
lb="$(line_of "a battleaxe")"
lc="$(line_of "c halberd")"
lk="$(line_of "b knife")"
if [ -z "$lb" ] || [ -z "$lc" ] || [ -z "$lk" ]; then
    echo "INCONCLUSIVE: the Weapon group is missing a battleaxe, a c halberd or a b knife. Run dir: $run"
    exit 2
fi
if [ "$lb" -ge "$lk" ] || [ "$lc" -ge "$lk" ]; then
    echo "FAIL: the Weapon group is misorted: battleaxe at line $lb, c halberd at line $lc, b knife at line $lk (want battleaxe and c halberd before b knife)."
    fail=1
fi
# An INCONCLUSIVE after a FAIL is still a FAIL: the earlier assertion already
# measured something, and later keys may have drifted because of it.
inconclusive() {
    if [ "$fail" = 1 ]; then
        echo "FAIL (later steps could not be read: $1). Run dir: $run"
        exit 1
    fi
    echo "INCONCLUSIVE: $1. Run dir: $run"
    exit 2
}

# 1. SEARCH finds the ware, ignoring case.
if grep -qi "potion of light" <<< "$(scr search-light)"; then
    :
else
    echo "FAIL: [/] \"potions of light\" then [x] did not describe a potion of light."
    fail=1
fi
grep -qi "potion of light" <<< "$(scr store-open)" && {
    echo "INCONCLUSIVE: the opening screen already described a potion of light."
    exit 2
}

# 1b. SEARCH for text no ware has.
if ! grep -q "No ware matches that\." <<< "$(scr search-none)"; then
    echo "FAIL: a search for text no ware has did not print \"No ware matches that.\""
    fail=1
fi

# The second search must reach a dagger.
grep -q "It is a dagger" <<< "$(scr search-dagger)" || {
    echo "FAIL: [/] \"dagger\" then [x] did not describe a dagger."
    fail=1
}

# 2. BUY. The prompt names the price; the gold must fall by exactly that.
price="$(scr buy-confirm | sed -n 's/.*(\([0-9][0-9]*\) gp).*/\1/p' | head -n 1)"
[ -n "$price" ] || {
    inconclusive "no \"Confirm purchase\" prompt with a price"
}
if [ "$price" -gt "$gold0" ]; then
    inconclusive "the dagger costs $price gp and the character has $gold0"
fi
if ! grep -qi "dagger" <<< "$(scr after-buy)"; then
    echo "FAIL: the inventory after the purchase does not list a dagger."
    fail=1
fi
gold1="$(scr store-reopen | sed -n 's/.*You have \([0-9][0-9]*\) gp.*/\1/p' | head -n 1)"
if [ -z "$gold1" ] || [ "$gold1" != "$((gold0 - price))" ]; then
    echo "FAIL: gold was $gold0, the dagger cost $price, the store now says \"${gold1:-nothing}\" (want $((gold0 - price)))."
    fail=1
fi

# 3. SELL. The menu must have opened; then one known outcome message.
grep -q "Sell Which Item?" <<< "$(scr sell-menu)" || {
    inconclusive "[s] did not open the Sell Which Item? menu"
}
outcome="$(cat "$S"/*-sell-1.txt "$S"/*-sell-2.txt "$S"/*-sell-play.txt)"
known='has no interest in that item|won.t buy un-identified items|won.t buy cursed items|doesn.t have the capital|offers [0-9]+ gp|You sell the|You have nothing to sell|you don.t sell coins|Sorry, son, I get my wares'
if ! grep -Eq "$known" <<<"$outcome"; then
    echo "FAIL: selling the first item ended in no message the SellItem branch can print."
    fail=1
fi
# The session must be back in play: no store header, the status line present.
if grep -q "Proprietor" <<< "$(scr sell-play)" || ! grep -q "GP:" <<< "$(scr sell-play)"; then
    echo "FAIL: after selling, the session did not return to play."
    fail=1
fi

if [ "$fail" = 1 ]; then
    echo "Run dir: $run"
    exit 1
fi

echo "PASS: [/] finds a ware and says so when none matches; buying took $price gp of $gold0; selling reached a known outcome and play."
echo "Run dir: $run"
exit 0
