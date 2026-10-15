#!/bin/bash
# gate: live
# Does character creation hand out starting-perk items uncursed? (bd inc-70nj)
#
# THE DEFECT. CreatePerk rejects cursed items and NamePerk shows its preview
# item uncursed (`it->IFlags &= (~IF_CURSED)`, src/Create.cpp near NamePerk),
# so the game's own text promises a clean starting item. But the grant path,
# BuildPerkItem (src/Create.cpp), called Item::MakeMagical and never cleared
# the flag, and MakeMagical rolls a fresh 50% curse for an EF_HALF_CURSED
# effect -- the Ring of Polymorphing, the cloak of Quietus. So a starting perk
# item that displays as uncursed in NamePerk arrived cursed half the time.
#
# THE ORACLE is INCURSION_PERK_CURSE_PROBE (src/Create.cpp PerkCurseProbe): at
# the end of Player::Create it builds N Ring of Polymorphing items through the
# SAME BuildPerkItem the grant uses, counts how many come out cursed, and logs
# one PERK_CURSE_PROBE line to the run's logs/errors.log. It is measurement
# only and returns at once with the variable unset. A run that lacks that
# line, or that logs a PERK_CURSE_PROBE error, measured nothing (exit 2).
#
# Usage: tools/check_perk_curse.sh
#   0 every seed handed out cursed=0
#   1 at least one seed handed out a cursed item
#   2 could not measure (missing probe line, probe error, or run-count skew)
# Quiet: one line per seed plus a total; runs live under logs/runs/.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
OPTIONS="$CHECK_OPTIONS"
SEEDS="1 2 3 4 5"

[ -x ./incursion-headless ] || _check_die 2 "incursion-headless is not built." \
    "Run: BACKEND=posix ./build_macos.sh"

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
FAIL=0; UNMEAS=0; NRUNS=0; NSEEDS=0; TOTAL=0
for seed in $SEEDS; do
    NSEEDS=$((NSEEDS + 1))
    RUN="$PWD/logs/runs/$STAMP-perk-curse-$seed"
    INCURSION_OPTIONS="$OPTIONS" INCURSION_PERK_CURSE_PROBE=40 \
        INCURSION_RUN_DIR="$RUN" \
        tools/headless.sh tools/keys/dive.keys "$seed" > "$RUN.out" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "seed $seed: UNMEASURED headless.sh exited $rc (see $RUN.out)"
        UNMEAS=1
        continue
    fi
    [ -d "$RUN" ] && NRUNS=$((NRUNS + 1))
    ERRLOG="$RUN/logs/errors.log"
    if [ ! -f "$ERRLOG" ]; then
        echo "seed $seed: UNMEASURED no errors.log under $RUN"
        UNMEAS=1
        continue
    fi
    if grep -q "PERK_CURSE_PROBE error=" "$ERRLOG"; then
        echo "seed $seed: UNMEASURED probe logged an error"
        UNMEAS=1
        continue
    fi
    LINE="$(grep -m1 "PERK_CURSE_PROBE grants=" "$ERRLOG")"
    if [ -z "$LINE" ]; then
        echo "seed $seed: UNMEASURED no PERK_CURSE_PROBE line"
        UNMEAS=1
        continue
    fi
    CURSED="$(printf '%s\n' "$LINE" | sed -n 's/.*cursed=\([0-9]*\).*/\1/p')"
    if [ -z "$CURSED" ]; then
        echo "seed $seed: UNMEASURED unreadable PERK_CURSE_PROBE line"
        UNMEAS=1
        continue
    fi
    TOTAL=$((TOTAL + CURSED))
    echo "seed $seed: cursed=$CURSED of 40"
    [ "$CURSED" -gt 0 ] && FAIL=1
done

if [ "$NRUNS" -ne "$NSEEDS" ]; then
    echo "UNMEASURED run directories ($NRUNS) != seeds ($NSEEDS)"
    UNMEAS=1
fi

echo "total: cursed=$TOTAL over $NSEEDS seeds"
if [ "$UNMEAS" -ne 0 ]; then
    echo "INCONCLUSIVE: a seed could not be measured."
    exit 2
fi
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: at least one seed handed out a cursed starting-perk item."
    exit 1
fi
echo "PASS: all $NSEEDS seeds handed out cursed=0 starting-perk items."
exit 0
