#!/bin/bash
# gate: live
# Does a shield-feat character end character creation with exactly ONE kite
# shield, not a stack of two? (inc-6fii)
#
# THE DEFECT. Universal Gear (lib/races.irh:47-56) grants a kite shield to any
# character carrying Shield Focus or Shield Expert, and the Paladin and Warrior
# class kits (lib/classes.irh, their Gear: lists) granted one too, so a
# Shield Expert paladin or warrior started with a stack the sheet reads as
# "2 kite shields". The fix is the creation-time pass DedupeStartingKit in
# src/Create.cpp, which removes duplicate base items and keeps the better copy,
# so the character ends with one kite shield.
#
# WHAT THIS CHECKS, per seed. A Human Paladin with the Shield Expert feat is
# built by tools/keys/kite-shield-expert.keys and the session saves once, which
# makes INCURSION_CHAR_PROBE=1 write logs/charprobe.txt (Game::SaveGame,
# src/Registry.cpp:1105-1111). Two independent facts must hold on that sheet:
#
#   1. The inventory names exactly one kite shield -- the string "kite shield"
#      appears, and the stacking form "2 kite shields" does NOT. A sheet that
#      never reached the inventory has neither, which is INCONCLUSIVE, not a
#      pass.
#   2. The Defense Class breakdown carries a shield term: the parenthesised line
#      under "Defense Class  N:" must contain "shield". The shield the character
#      has is a real one the engine counts, not merely a line of text.
#
# A missing logs/charprobe.txt, a missing Defense Class line, or a missing
# parenthesised breakdown is INCONCLUSIVE (exit 2), never a pass: a sheet that
# did not reach the state cannot witness either the defect or its absence.
#
# Usage: tools/check_kite_shield_once.sh
#   0 every seed ended with exactly one kite shield and a shield Defense term
#   1 at least one seed stacked two kite shields, or lost its Defense shield term
#   2 could not measure (no charprobe.txt, no Defense Class line, or a bad run)
# Quiet: one line per seed plus a total; runs live under logs/runs/.
#
# Options file: tools/fixtures/options-2026-08-22.dat. Seeds: 1 2 3.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
OPTIONS="$CHECK_OPTIONS"
SEEDS="1 2 3"
KEYS="tools/keys/kite-shield-expert.keys"

[ -x ./incursion-headless ] || _check_die 2 "incursion-headless is not built." \
    "Run: BACKEND=posix ./build_macos.sh"

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
FAIL=0; UNMEAS=0; NRUNS=0; NSEEDS=0
for seed in $SEEDS; do
    NSEEDS=$((NSEEDS + 1))
    RUN="$PWD/logs/runs/$STAMP-kite-shield-$seed"
    INCURSION_OPTIONS="$OPTIONS" INCURSION_CHAR_PROBE=1 \
        INCURSION_RUN_DIR="$RUN" \
        tools/headless.sh "$KEYS" "$seed" > "$RUN.out" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "seed $seed: UNMEASURED headless.sh exited $rc (see $RUN.out)"
        UNMEAS=1
        continue
    fi
    [ -d "$RUN" ] && NRUNS=$((NRUNS + 1))
    PROBE="$RUN/logs/charprobe.txt"
    if [ ! -f "$PROBE" ]; then
        echo "seed $seed: UNMEASURED no logs/charprobe.txt under $RUN"
        UNMEAS=1
        continue
    fi

    # (1) Exactly one kite shield. The stack line is the defect's own shape, so
    # it is read first and names the failure directly; the singular line is the
    # positive record that the character has the shield at all.
    STACKED="$(grep -c "^ *2 kite shields" "$PROBE")"
    SINGULAR="$(grep -c "kite shield" "$PROBE")"
    if [ "$STACKED" -gt 0 ]; then
        echo "seed $seed: FAIL character holds a stack of two kite shields"
        FAIL=1
        continue
    fi
    if [ "$SINGULAR" -eq 0 ]; then
        echo "seed $seed: UNMEASURED no kite shield in the inventory"
        UNMEAS=1
        continue
    fi

    # (2) The Defense Class breakdown carries a shield term. Line N is
    # "Defense Class  <n>:"; the parenthesised breakdown is the next line and
    # must contain the word "shield". A sheet with no Defense line cannot be
    # read, so it is INCONCLUSIVE.
    DEFLINE="$(grep -n "^Defense Class " "$PROBE" | head -1 | cut -d: -f1)"
    if [ -z "$DEFLINE" ]; then
        echo "seed $seed: UNMEASURED no Defense Class line in charprobe.txt"
        UNMEAS=1
        continue
    fi
    BREAKDOWN="$(sed -n "$((DEFLINE + 1))p" "$PROBE")"
    case "$BREAKDOWN" in
        *shield*) ;;
        *) echo "seed $seed: FAIL Defense Class breakdown has no shield term: $BREAKDOWN"
           FAIL=1
           continue ;;
    esac
    echo "seed $seed: ok one kite shield, Defense Class carries a shield term"
done

if [ "$NRUNS" -ne "$NSEEDS" ]; then
    echo "UNMEASURED run directories ($NRUNS) != seeds ($NSEEDS)"
    UNMEAS=1
fi

if [ "$UNMEAS" -ne 0 ]; then
    echo "INCONCLUSIVE: a seed could not be measured."
    exit 2
fi
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: a shield-feat character did not end with exactly one counted kite shield."
    exit 1
fi
echo "PASS: all $NSEEDS seeds ended with exactly one kite shield and a shield Defense term."
exit 0
