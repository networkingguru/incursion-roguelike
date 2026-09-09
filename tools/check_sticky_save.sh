#!/bin/bash
# inc-18q6 phase 5, R19/R20. Sticky terrain (pool of slime) must roll a real
# Reflex save against a DC above zero, and the STUCK it grants must lapse on
# its own if the victim never escapes.
#
# THE DEFECT. src/Move.cpp's sticky-terrain path in Creature::TerrainEffects
# threw AD_STUK through the DAMAGE macro without ever setting saveDC.
# EventInfo::Clear() (inc/Events.h) memsets the struct, so it arrived as 0,
# and Creature::SavingThrow (src/Creature.cpp) returns false -- printing
# NOTHING -- for DC <= 0: an automatic failure, not an automatic pass, and
# no "Reflex Save:" line was ever possible for this hazard (R19). The same
# call passed -1 as the duration, and Thing::UpdateStati (src/Status.cpp)
# only ever decrements a Duration greater than zero, so the STUCK it granted
# never expired (R20).
#
# THE ORACLE, R19: the printed "Reflex Save: ... vs DC <n> [...]" line on the
# turn the subject gets stuck, with n > 0. That line cannot print at all on
# the unfixed tree.
#
# THE ORACLE, R20, and why "still Stuck" is not read directly. Pool of
# slime's hazard check re-runs every turn a creature stands on it, guarded
# only by "not already Stuck" -- so a creature who does nothing but wait
# gets caught again the instant the old grant expires, correctly: he never
# left the puddle. That makes the status line alone useless here; both a
# permanently-stuck creature and a finite one that keeps getting re-caught
# show "Stuck" forever. The signal this script reads instead: the printed
# roll line CHANGES after a long wait of nothing but "." (Wait One Turn). A
# different d20 result -- and, once ENTANGLED's -4 Dexterity joins the mix,
# a different modifier -- can only mean a second roll happened, which can
# only happen if the first grant expired, which requires a finite Duration.
# On the unfixed tree (Duration -1) the line can never change no matter how
# long the wait runs, because the original grant never lapses and the guard
# blocks any second roll.
#
# THE GUARD: no "Escape Artist Check:", "Strength Check:", "You tear free!"
# or "You remain stuck fast!" may appear anywhere in the run. Every key sent
# after getting stuck is "." -- nothing in this fixture ever tries to move
# or escape -- so none of those lines has any legitimate way to appear. Any
# of them would mean the change came from the escape mechanic, not Duration,
# and the check must not pass.
#
# Prove red by reverting either half in src/Move.cpp: put back
# `DAMAGE(this, this, AD_STUK, -1, NAME(stickyID), xe.EParam = ...)` (drops
# both the saveDC and the duration) and rebuild.
#
# Usage: tools/check_sticky_save.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=4
KEYS=tools/keys/sticky-save.keys

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
       INCURSION_MAP_AUDIT=0 tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script could not find something on screen."
    echo "              Menu letters move when a list changes. Run: $run"
    exit 2
fi
[ -n "$run" ] && [ -d "$run/logs/screens" ] || {
    echo "INCONCLUSIVE: no run directory. Output was:"; echo "$out"; exit 2; }

S="$run/logs/screens"
stuck="$(ls "$S"/*-got-stuck.txt 2>/dev/null | head -1)"

# --- preconditions.

[ -f "$stuck" ] || { echo "INCONCLUSIVE: no screen dumped at $stuck"; exit 2; }

grep -qh " Stuck " "$stuck" || {
    echo "INCONCLUSIVE: the subject never got stuck on pool of slime, so"
    echo "              nothing was measured. Screen: $stuck"
    exit 2
}

rc=0

# --- R19: a real Reflex roll, against a DC above zero, on the turn he got
# stuck. This is the line SavingThrow cannot print at all when DC <= 0.

stuck_roll="$(grep -h "^Reflex Save:" "$stuck" | sed 's/ *|.*//')"
if [ -z "$stuck_roll" ]; then
    echo "FAIL: no \"Reflex Save:\" line printed on the turn the subject got"
    echo "      stuck. SavingThrow prints nothing at all for DC <= 0, so this"
    echo "      is the unfixed tree's signature, not a coincidence."
    rc=1
elif ! echo "$stuck_roll" | grep -q "vs DC 0 \|vs DC -"; then
    dc="$(echo "$stuck_roll" | sed -n 's/.*vs DC \([0-9-]*\).*/\1/p')"
    if [ -z "$dc" ] || [ "$dc" -le 0 ] 2>/dev/null; then
        echo "FAIL: the Reflex save rolled against DC $dc, which is not a"
        echo "      difficulty. Line: $stuck_roll"
        rc=1
    fi
else
    echo "FAIL: the Reflex save rolled against DC 0 or below:"
    echo "      $stuck_roll"
    rc=1
fi

# --- the guard: nothing here may look like an escape. Every key sent after
# getting stuck is "." (Wait One Turn); none of these lines has a legitimate
# way to appear, and their presence would mean the R20 signal below came
# from escaping rather than from Duration.

bad="$(grep -lh "Escape Artist Check:\|Strength Check:\|You tear free\|You remain stuck fast" "$S"/* 2>/dev/null || true)"
if [ -n "$bad" ]; then
    echo "FAIL: an escape-mechanic line appeared, so this run is not the"
    echo "      passive wait it needs to be:"
    echo "$bad" | sed 's/^/      /'
    rc=1
fi

# --- R20: the printed roll line must CHANGE after a long wait of nothing
# but waiting -- proof a second roll happened, which requires the first
# grant to have expired. "Still Stuck" alone proves nothing here (see the
# header): a finite Duration that keeps re-catching him on the same puddle
# looks identical to a permanent one on the status line.

waited="$(ls "$S"/*-wait100.txt 2>/dev/null | head -1)"
[ -f "$waited" ] || { echo "INCONCLUSIVE: no screen dumped at $waited"; exit 2; }

waited_roll="$(grep -h "^Reflex Save:\|^Balance Check:" "$waited" | sed 's/ *|.*//')"
if [ -z "$waited_roll" ]; then
    echo "FAIL: no roll line at all was showing after the wait. Screen: $waited"
    rc=1
elif [ "$waited_roll" = "$stuck_roll" ]; then
    echo "FAIL: the roll line after 100 turns of nothing but waiting is"
    echo "      IDENTICAL to the one that got him stuck:"
    echo "      $stuck_roll"
    echo "      A permanent grant (Duration -1) would show exactly this: the"
    echo "      same stale line forever, because no second roll ever fires."
    rc=1
fi

if [ "$rc" = 0 ]; then
    echo "PASS: sticky terrain rolls a real Reflex save, and the STUCK it"
    echo "      grants lapses on its own."
    echo "      Got stuck:        $stuck_roll"
    echo "      100 turns later:  $waited_roll"
fi
echo "      run: $run"
exit $rc
