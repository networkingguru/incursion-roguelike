#!/bin/bash
# gate: live
# Do starting-perk items keep the qualities the generator rolled? (bd inc-4qni)
#
# THE DEFECT. CreatePerk's PERK_ITEM case stores quality `i` (the perk number,
# 0-2) into every quality slot:
#     Perks.elt[I(i,3)].p.i.q[I(q,8)] = it->GetQuality(i);
# but the loop index is `q`, so the item qualities the generator rolled are
# never copied. BuildPerkItem (src/Create.cpp) later rebuilds the granted item
# from those slots, so the granted item's quality set differs from the set the
# generator produced.
#
# THE ORACLE is INCURSION_PERK_QUALITY_PROBE (src/Create.cpp PerkQualityProbe):
# at the end of Player::Create it calls CreatePerk directly with a capture flag
# set, records the rolled qualities, rebuilds the granted item through the SAME
# BuildPerkItem the grant uses, and compares the nonzero quality sets. It logs
# one PERK_QUALITY_PROBE line to the run's logs/errors.log. It is measurement
# only and returns at once with the variable unset. A run that lacks that line,
# that logs a probe error, or that measured nothing useful (withq=0 or
# nocapture>0) measured nothing (exit 2).
#
# Usage: tools/check_perk_quality.sh
#   0 every seed's granted qualities matched the generated qualities
#   1 at least one seed matched nothing (mismatch > 0)
#   2 could not measure (missing/unreadable line, or run-count skew)
# Quiet: one line per seed plus a total; runs live under logs/runs/.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
OPTIONS="$CHECK_OPTIONS"
SEEDS="1 2 3 4 5"

[ -x ./incursion-headless ] || _check_die 2 "incursion-headless is not built." \
    "Run: BACKEND=posix ./build_macos.sh"

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
FAIL=0; UNMEAS=0; NRUNS=0; NSEEDS=0
TOTALMIS=0; TOTALWQ=0
for seed in $SEEDS; do
    NSEEDS=$((NSEEDS + 1))
    RUN="$PWD/logs/runs/$STAMP-perk-quality-$seed"
    INCURSION_OPTIONS="$OPTIONS" INCURSION_PERK_QUALITY_PROBE=40 \
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
    LINE="$(grep -m1 "PERK_QUALITY_PROBE items=" "$ERRLOG")"
    if [ -z "$LINE" ]; then
        echo "seed $seed: UNMEASURED no PERK_QUALITY_PROBE line"
        UNMEAS=1
        continue
    fi
    WQ="$(printf '%s\n' "$LINE" | sed -n 's/.*withq=\([0-9]*\).*/\1/p')"
    MIS="$(printf '%s\n' "$LINE" | sed -n 's/.*mismatch=\([0-9]*\).*/\1/p')"
    NOC="$(printf '%s\n' "$LINE" | sed -n 's/.*nocapture=\([0-9]*\).*/\1/p')"
    if [ -z "$WQ" ] || [ -z "$MIS" ] || [ -z "$NOC" ]; then
        echo "seed $seed: UNMEASURED unreadable PERK_QUALITY_PROBE line"
        UNMEAS=1
        continue
    fi
    if [ "$WQ" -eq 0 ] || [ "$NOC" -gt 0 ]; then
        echo "seed $seed: UNMEASURED withq=$WQ nocapture=$NOC (measured nothing)"
        UNMEAS=1
        continue
    fi
    TOTALMIS=$((TOTALMIS + MIS)); TOTALWQ=$((TOTALWQ + WQ))
    echo "seed $seed: mismatch=$MIS of withq $WQ"
    [ "$MIS" -gt 0 ] && FAIL=1
done

if [ "$NRUNS" -ne "$NSEEDS" ]; then
    echo "UNMEASURED run directories ($NRUNS) != seeds ($NSEEDS)"
    UNMEAS=1
fi

echo "total: mismatch=$TOTALMIS of withq $TOTALWQ"
if [ "$UNMEAS" -ne 0 ]; then
    echo "INCONCLUSIVE: a seed could not be measured."
    exit 2
fi
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: granted qualities differ from generated qualities."
    exit 1
fi
echo "PASS: all $NSEEDS seeds matched the generated qualities."
exit 0
