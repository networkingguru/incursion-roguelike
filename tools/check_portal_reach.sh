#!/bin/bash
# Does every portal on a generated level share one PASSABLE component with
# every other portal? (inc-5caj)
#
# Usage: tools/check_portal_reach.sh [seed ...]
#        tools/check_portal_reach.sh              # seeds 1..20
#        tools/check_portal_reach.sh 4 17          # just those two
#        tools/check_portal_reach.sh --prove-red [seed ...]
#                                                   # see PROVE-RED below
#
# Exit: 0 PASS -- every KEPT level (see below) reported stranded=0
#       1 FAIL -- a kept level stranded a portal outside the door-aware
#         component that holds the most portals, OR no PORTALREACH line was
#         produced at all
#
# PROVE-RED. A guard that cannot be shown failing is not evidence
# (incursion-verification-oracles-that-cannot-fail). --prove-red runs with
# INCURSION_PORTAL_REPAIR_OFF=all -- Map::RepairStrandedPortals and
# src/Feature.cpp's regeneration retry both become no-ops (bd inc-5caj) -- and
# INVERTS the verdict: PASS (exit 0) only when the underlying check FAILS,
# i.e. a stranded portal was actually measured; FAIL (exit 1) if it stayed
# green, because that means this run could not demonstrate the defect it
# exists to catch. Defaults to the eight seeds phase 1 and phase 2 both found
# stranded (3 5 6 9 11 13 15 16), not 1-20, so a caller who wants to see it go
# red does not have to wait for the whole sweep.
#
# WHAT IS BEING MEASURED, AND WHY TWO COUNTS. src/MakeLev.cpp:1762-1770
# forces every up staircase onto the down staircase above it; when that
# square is solid it opens the one square and seals its eight neighbours as
# "dungeon wall", leaving the best-effort "Final, Fix-Up Tunneling" pass
# (src/MakeLev.cpp:1778-1900) to reopen the pocket. That pass sometimes
# misses one. PortalReachProbe (src/MakeLev.cpp) measures this with a
# component walk over squares Map::SolidAt calls open -- BUT a closed door is
# Solid (src/Feature.cpp:571-583), so that walk alone turns every room behind
# a door into its own component and wildly overcounts. The probe's DOOR-AWARE
# walk instead treats a door square as passable regardless of open/closed,
# the same rule Map::FloodConnectA already uses (src/MakeLev.cpp:3882). This
# check fails on the door-aware count (`stranded=`) only, and prints the
# door-blind count (`stranded_nodoor=`) purely for contrast.
#
# ONE LEVEL, MAYBE SEVERAL PROBE LINES. Map::RepairStrandedPortals carves a
# corridor to a stranded portal; when it cannot, Game::GetDungeonMap
# (src/Feature.cpp) discards that Map and generates the depth again, up to 10
# times. PortalReachProbe runs inside Map::Generate itself, so a discarded
# attempt still writes its own PORTALREACH line -- it was measured honestly,
# and then thrown away. Judging every line equally would fail this check on
# every regeneration, including the ones the fix already caught and fixed. So
# for each depth this reads only the LAST PORTALREACH line -- the one for the
# Map that was actually kept and handed to the player -- and reports how many
# attempts it took beside it. An earlier, discarded stranded attempt is not
# printed as a failure; `attempts=N` on the kept line is how a reader sees a
# regeneration happened at all.
#
# WHY A RUN THAT MEASURED NOTHING IS A FAIL, NOT A PASS. A check that stays
# green because the probe never fired would be exactly the oracle
# tools/README.md warns against: "verified" standing in for "unknown". See
# incursion-verification-oracles-that-cannot-fail in the project's own rules.
#
# Run directories are never deleted by this script -- they are the raw
# evidence a stranded-portal report is based on.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROVE_RED=0
if [ "${1:-}" = "--prove-red" ]; then
    PROVE_RED=1
    shift
fi

SEEDS=("$@")
if [ ${#SEEDS[@]} -eq 0 ]; then
    if [ "$PROVE_RED" -eq 1 ]; then
        SEEDS=(3 5 6 9 11 13 15 16)
    else
        SEEDS=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)
    fi
fi

PROVE_RED_OFF=""
[ "$PROVE_RED" -eq 1 ] && PROVE_RED_OFF="all"

[ -x ./incursion-headless ] || {
    echo "COULD NOT MEASURE: ./incursion-headless not built."
    echo "  Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

# Collapses a portalreach.log to one line per DEPTH -- the last PORTALREACH
# summary line seen for it, tagged with how many attempts that depth took --
# followed by that attempt's own PORTALREACH_STRANDED/_NBR lines, if any.
# Regeneration retries for one depth are always consecutive (Game::GetDungeonMap
# loops on one depth before moving to the next), so "the block since the
# previous summary line" is always the block belonging to it.
FINAL_AWK="$ROOT/tools/portal_reach_final.awk"
cat > "$FINAL_AWK" << 'AWKEOF'
BEGIN { block = ""; curd = "" }
/^PORTALREACH_STRANDED / || /^PORTALREACH_NBR / { block = block $0 "\n"; next }
/^PORTALREACH / {
    if (curd != "") { finalblock[curd] = block }
    split($2, a, "=")
    d = a[2] + 0
    final[d] = $0
    if (!(d in seen)) { order[++n] = d; seen[d] = 1 }
    attempts[d]++
    block = ""
    curd = d
    next
}
END {
    if (curd != "") finalblock[curd] = block
    for (i = 1; i <= n; i++) {
        d = order[i]
        printf "%s attempts=%d\n", final[d], attempts[d]
        printf "%s", finalblock[d]
    }
}
AWKEOF

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
WORK="$ROOT/logs/portal-reach/$STAMP"
mkdir -p "$WORK"

echo "seeds:  ${SEEDS[*]}"
echo "into:   $WORK"
echo

fail=0
levels_seen=0
seeds_with_data=0
stranded_reports=0
stranded_nodoor_reports=0
regenerated_depths=0
declare -a STRANDED_RUNDIRS

for seed in "${SEEDS[@]}"; do
    # A name unique to this check AND this seed: two seeds sharing one run
    # directory would share one append-mode portalreach.log, and the counts
    # for each seed would come out wrong (tools/README.md, the merged-log trap
    # that first mis-measured inc-90u).
    RUNDIR="$WORK/seed-$seed"

    INCURSION_PORTAL_PROBE=1 \
    INCURSION_PORTAL_REPAIR_OFF="${PROVE_RED_OFF:-}" \
    INCURSION_OPTIONS=tools/gates/Options.Dat \
    INCURSION_RUN_DIR="$RUNDIR" \
        tools/headless.sh tools/keys/dive.keys "$seed" > "$RUNDIR.out" 2>&1

    LOG="$RUNDIR/logs/portalreach.log"
    if [ ! -f "$LOG" ]; then
        echo "seed $seed: no logs/portalreach.log -- the probe never fired."
        echo "  session output: $RUNDIR.out"
        continue
    fi

    FINAL="$RUNDIR/logs/portalreach.final"
    awk -f "$FINAL_AWK" "$LOG" > "$FINAL"

    seed_levels="$(grep -c '^PORTALREACH ' "$FINAL" || true)"
    [ "$seed_levels" -gt 0 ] || {
        echo "seed $seed: portalreach.log exists but holds no PORTALREACH line."
        continue
    }

    seeds_with_data=$((seeds_with_data + 1))
    levels_seen=$((levels_seen + seed_levels))

    seed_regen="$(grep '^PORTALREACH ' "$FINAL" | grep -cv ' attempts=1$' || true)"
    regenerated_depths=$((regenerated_depths + seed_regen))

    # Door-aware (the verdict) and door-blind (contrast only) counts, read
    # from the KEPT level's own summary line only.
    seed_stranded="$(grep '^PORTALREACH ' "$FINAL" | grep -cv ' stranded=0 ' || true)"
    seed_stranded_nodoor="$(grep '^PORTALREACH ' "$FINAL" | grep -cv ' stranded_nodoor=0 ' || true)"
    stranded_nodoor_reports=$((stranded_nodoor_reports + seed_stranded_nodoor))

    echo "seed $seed: $seed_levels level(s), $seed_regen regenerated; kept-level door-aware stranded=$seed_stranded, door-blind stranded_nodoor=$seed_stranded_nodoor"

    if [ "$seed_stranded" -gt 0 ]; then
        fail=1
        stranded_reports=$((stranded_reports + seed_stranded))
        STRANDED_RUNDIRS+=("$RUNDIR")
        # The kept level's own summary line, for every depth that is still
        # stranded after every regeneration attempt, plus its own
        # PORTALREACH_STRANDED / PORTALREACH_NBR detail.
        grep '^PORTALREACH ' "$FINAL" | grep -v ' stranded=0 ' | sed 's/^/    /'
        grep -E '^PORTALREACH_(STRANDED|NBR) ' "$FINAL" | sed 's/^/    /'
    fi
done

rm -f "$FINAL_AWK"

echo
if [ "$seeds_with_data" -eq 0 ]; then
    echo "FAIL: no seed produced a single PORTALREACH line. The probe never"
    echo "      measured anything -- check INCURSION_PORTAL_PROBE is read by"
    echo "      the binary under test, and that dive.keys reaches a generated"
    echo "      level on at least one of: ${SEEDS[*]}"
    exit 1
fi

echo "examined: $levels_seen kept level(s) across $seeds_with_data of ${#SEEDS[@]} seed(s), $regenerated_depths regenerated at least once"
[ "$seeds_with_data" -lt ${#SEEDS[@]} ] &&
    echo "          $(( ${#SEEDS[@]} - seeds_with_data )) seed(s) produced no data -- see above"
echo "door-blind stranded_nodoor total on kept levels (contrast only, not the verdict): $stranded_nodoor_reports level-report(s)"

# Distribution of comp_open across every door-aware-stranded portal on a KEPT
# level, across every seed -- so a reader can tell a one-square pocket (the
# reported bug's shape) from a merely large disconnected wing.
all_stranded_lines="$(grep -rh '^PORTALREACH_STRANDED ' "$WORK"/seed-*/logs/portalreach.final 2>/dev/null || true)"
if [ -n "$all_stranded_lines" ]; then
    echo
    echo "comp_open distribution across all kept-level door-aware-stranded portals:"
    printf '%s\n' "$all_stranded_lines" |
        grep -oE 'comp_open=[0-9]+' | cut -d= -f2 | sort -n | uniq -c |
        awk '{printf "  comp_open=%-8s %d portal(s)\n", $2, $1}'
fi

if [ "$PROVE_RED" -eq 1 ]; then
    echo
    if [ "$fail" -eq 1 ]; then
        echo "PASS (--prove-red): $stranded_reports kept level(s) stranded a portal"
        echo "      with INCURSION_PORTAL_REPAIR_OFF=all -- the check can be shown"
        echo "      failing, so a green run of the plain sweep is evidence."
        echo "Run dirs (not deleted, holding stranded reports):"
        printf '  %s\n' "${STRANDED_RUNDIRS[@]}"
        exit 0
    fi
    echo "FAIL (--prove-red): every kept level stayed connected even with"
    echo "      INCURSION_PORTAL_REPAIR_OFF=all. This run could not demonstrate"
    echo "      the defect the check exists to catch -- do not trust a green"
    echo "      plain-sweep result until this can be shown red again."
    echo "Run dirs: $WORK"
    exit 1
fi

if [ "$fail" -eq 1 ]; then
    echo
    echo "FAIL: $stranded_reports kept level(s) stranded at least one portal"
    echo "      outside the door-aware component holding the most portals,"
    echo "      even after every regeneration attempt."
    echo "Run dirs (not deleted, holding stranded reports):"
    printf '  %s\n' "${STRANDED_RUNDIRS[@]}"
    exit 1
fi

echo
echo "PASS: every kept level examined shares one door-aware passable"
echo "      component across every portal."
echo "Run dirs: $WORK"
exit 0
