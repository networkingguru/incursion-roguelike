#!/bin/bash
# Does this build play the same game when its objects sit somewhere else?
#
# Usage: tools/check_layout.sh [seed] [keyscript]
#        tools/check_layout.sh 3 tools/keys/dive12.keys     # the default
#        for s in 1 2 3 4 5; do tools/check_layout.sh $s; done   # a sweep
#
# Exit: 0 the seed played the same game in both layouts
#       1 IT DID NOT -- this build reads a memory address as if it were data
#       2 nothing was measured, and the reason is printed
#
# WHAT THIS IS FOR. inc-dhc is not one bug, it is a class: the engine somewhere
# compares two addresses, the allocator puts objects somewhere different on
# every launch, and the same seed plays a different game. One site is fixed
# (TargetSort, commit 2f0100b) and at least one more is live. Hunting them by
# running a seed twenty times and hoping it splits costs about an hour a site.
# This makes it an experiment instead: one seed, two stated layouts, and the
# screens must match.
#
# HOW IT AVOIDS PROVING NOTHING. Four sessions run, not two. Each layout runs
# TWICE, and the pair must be byte-identical before any comparison between
# layouts is believed. That is the control: if a layout does not repeat itself,
# then something other than the layout is moving, the verdict would be noise,
# and this exits 2 rather than reporting a result. Every session must also have
# reached a map -- a session that dies in character generation agrees perfectly
# with another session that died in character generation, and that false
# agreement is how a fix got published on 2026-08-14 that fixed nothing.
#
# WHY IT NEEDS lldb. The two layouts must differ ONLY by the amount asked for,
# so the machine's own address randomisation has to be off while they run.
# lldb switches it off. Nothing is debugged; lldb is used as a launcher, and it
# eats the exit code, which is why every judgement below is made from what the
# session left on disk.
#
# WHY THE LAYOUT NUMBERS ARE NOT 0 AND 1. 0 means stock: no padding anywhere.
# Comparing 0 with 3 would change the geometry AND whether padding exists at
# all, which is two changes. Two non-zero numbers change the geometry only.
# See the comment on HeapPad in src/Base.cpp.
#
# WHAT A PASS DOES NOT MEAN. It means this seed, on this key script, did not
# reach a site that reads an address. Another seed still can. The class is
# closed only when a sweep of many seeds passes, and it stays closed only
# because this fails again the moment somebody writes another one.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${1:-3}"
KEYS="${2:-tools/keys/dive12.keys}"
BIN="${LAYOUT_BIN:-./incursion-probe}"
# Two arbitrary non-zero numbers. Any two differing ones work; these are the
# ones the committed evidence was taken with.
A="${LAYOUT_A:-1}"
B="${LAYOUT_B:-3}"

[ -f "$KEYS" ] || { echo "no such key script: $KEYS"; exit 2; }

[ -x "$BIN" ] || {
    echo "$BIN not built. The layout knob only exists in the probe build:"
    echo "  EXTRA_CXXFLAGS=-DDIVERGE_PROBE OUT=incursion-probe BACKEND=posix ./build_macos.sh"
    exit 2
}

command -v lldb > /dev/null || {
    echo "lldb not found. It is needed to switch address randomisation off,"
    echo "without which the two layouts differ by more than this asks for."
    exit 2
}

WORK="${LAYOUT_DIR:-$ROOT/logs/layout/$(date +%Y%m%d-%H%M%S)-$$}"
mkdir -p "$WORK"

echo "seed:     $SEED"
echo "script:   $KEYS"
echo "binary:   $BIN"
echo "layouts:  $A and $B, each run twice"
echo "into:     $WORK"
echo

# -headless is required. Under lldb the game inherits lldb's terminal, sees
# 80x24, decides it cannot draw and exits before it plays anything.
run_one() {
    local layout="$1" tag="$2"
    INCURSION_BIN="$BIN" \
    INCURSION_LAUNCHER="lldb -b -o run -o quit --" \
    INCURSION_LAYOUT="$layout" \
    INCURSION_RUN_DIR="$WORK/$tag" \
        ./tools/headless.sh "$KEYS" "$SEED" -headless > "$WORK/$tag.out" 2>&1
}

for pair in "$A:a1" "$A:a2" "$B:b1" "$B:b2"; do
    run_one "${pair%%:*}" "${pair##*:}"
done

# ---- did every session actually play? ----------------------------------
for tag in a1 a2 b1 b2; do
    screens="$(ls "$WORK/$tag/logs/screens" 2>/dev/null | wc -l | tr -d ' ')"
    if [ ! -f "$WORK/$tag/logs/mapaudit.log" ] || [ "$screens" -eq 0 ]; then
        echo "COULD NOT MEASURE: session $tag never entered a map ($screens screens)."
        echo "  Its output is in $WORK/$tag.out. Check that Options.Dat in this"
        echo "  tree is the one you meant to test with, and that the key script"
        echo "  reaches gameplay for this seed."
        exit 2
    fi
done

same() { diff -rq "$WORK/$1/logs/screens" "$WORK/$2/logs/screens" > /dev/null 2>&1; }

# ---- the control: each layout must repeat itself ------------------------
for pair in "a1 a2 $A" "b1 b2 $B"; do
    set -- $pair
    if ! same "$1" "$2"; then
        echo "COULD NOT MEASURE: layout $3 did not repeat itself."
        echo "  Two sessions with identical seed, script and layout produced"
        echo "  different screens, so something other than the layout is moving"
        echo "  and any comparison between layouts would be noise."
        echo "  Most likely address randomisation is still on: check that lldb"
        echo "  runs on this machine and that target.disable-aslr is true."
        echo "  Screens: $WORK/$1/logs/screens and $WORK/$2/logs/screens"
        exit 2
    fi
done
echo "control:  layout $A repeated itself, and so did layout $B"

# ---- the measurement ----------------------------------------------------
if same a1 b1; then
    echo
    echo "PASS -- seed $SEED played the same game in both layouts."
    echo "        This seed and script reached no site that reads an address."
    exit 0
fi

echo
echo "FAIL -- seed $SEED played a DIFFERENT game when its objects moved."
echo "        This build reads a memory address as if it were data. See inc-dhc."
echo

FIRST="$(diff -rq "$WORK/a1/logs/screens" "$WORK/b1/logs/screens" 2>&1 | head -1)"
echo "  first screen that differs:"
echo "    $FIRST"

# The probe build counts every random number drawn and prints the running total
# at map generation, at each creature's action and at the target list. Both runs
# draw the same numbers in the same order until something changes a decision, so
# the first probe line whose count differs is the place they stopped playing the
# same game. That is the line to start reading code from.
grep '^PROBE' "$WORK/a1.out" > "$WORK/a1.probe" 2>/dev/null
grep '^PROBE' "$WORK/b1.out" > "$WORK/b1.probe" 2>/dev/null
if [ -s "$WORK/a1.probe" ] && [ -s "$WORK/b1.probe" ]; then
    echo
    echo "  the two runs drew the same random numbers until here:"
    diff "$WORK/a1.probe" "$WORK/b1.probe" | head -6 | sed 's/^/    /'
    echo
    echo "  full probe traces: $WORK/a1.probe and $WORK/b1.probe"
fi

echo
echo "  screens kept in $WORK"
exit 1
