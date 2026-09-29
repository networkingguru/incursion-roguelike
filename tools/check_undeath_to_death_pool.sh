#!/bin/bash
# gate: live
# inc-kgzx phase 2c: does Undeath to Death spend, cap and waste its Hit Dice
# pool by the SRD rule, with all three seen in play rather than read off code?
#
# tools/check_undeath_to_death.sh covers the first scene, which never spends
# the pool short: two 1-HD claws cost 2 and every seed rolls 11d4 >= 11. Three
# rules were therefore only Asserted from the source:
#   R1 fewest Hit Dice first, ties to the one nearest the centre;
#   R2 a remainder too small for the next creature is wasted and the walk stops;
#   R3 the 9-HD cap -- and, behind it, that the spell's undead filter
#      (EF_LIM_MTYPE, tval MA_UNDEAD) accepts a bodak at all. If it did not, the
#      cap was never reached and R3 was never tested.
#
# THE SCENES, built by tools/keys/undeath-to-death-pool.keys (the caster is the
# same orc priest of Aiswin at character level 11, so the pool is 11d4 = 11..44
# per cast). The key file explains why a single burst cannot show R2 and R3
# together: the walk sorts fewest Hit Dice first, so a 9-HD bodak is always
# last, and a burst whose sub-cap creatures already exceed the pool always
# stops before it. The scene therefore casts twice:
#
#   BURST ONE, centre caster+4 east: two crawling claws (1 HD) and six mummies
#     (8 HD), 50 HD of eligible creatures against a maximum pool of 44, plus a
#     bodak near the centre. Every seed strikes both claws (R1 order) then the
#     mummies fewest-HD/nearest first until the remainder is under 8, where a
#     mummy is WASTE-STOP (R2). The bodak, being accepted, is never a
#     REJECT-TARGET line.
#   BURST TWO, centre caster-6 east (disjoint): one crawling claw and one
#     bodak. The pool covers the claw and then reaches the bodak, which the cap
#     skips: SKIP-CAP, never REJECT-TARGET, never STRIKE. That SKIP-CAP line is
#     what proves the undead filter accepts a bodak (R3).
#
# THE ORACLE is the probe log (INCURSION_HDPOOL_PROBE=1, logs/hdpoolprobe.log),
# which names every candidate in walk order with its square, Hit Dice, distance,
# remaining pool and the action (STRIKE/SKIP-CAP/WASTE-STOP), plus every
# rejected creature (REJECT-TARGET); and the game's own message log, whose
# "<name>'s Will Save:" lines are one per struck creature, saved or not.
#
# A MISSING OR EMPTY PROBE LOG IS A FAIL, not an inconclusive: the probe IS the
# measurement, and a run that left none measured nothing.
#
# Usage: tools/check_undeath_to_death_pool.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/undeath-to-death-pool.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
POOL_MIN=11
POOL_MAX=44

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

fail() { echo "FAIL: $*"; exit 1; }

mkdir -p logs/inc-kgzx/pool

PASS_SEEDS=""

for SEED in $(seq 1 10); do
    RUN="logs/inc-kgzx/pool/seed-$SEED"
    rm -rf "$RUN"
    OUT="$(INCURSION_TARGET_PROBE=1 INCURSION_HDPOOL_PROBE=1 \
        INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$RUN" \
        tools/headless.sh "$KEYS" "$SEED" 2>&1)"
    STATUS=$?

    if grep -q "NO GAMEPLAY" <<< "$OUT"; then
        fail "seed $SEED never entered a map, so it measured nothing."
    fi
    if [ "$STATUS" -ne 0 ]; then
        echo "$OUT" | tail -20
        fail "seed $SEED: tools/headless.sh exited $STATUS."
    fi

    PROBE="$RUN/logs/hdpoolprobe.log"
    [ -s "$PROBE" ] ||
        fail "seed $SEED: no (or empty) hdpoolprobe.log, so the pool was never measured. specimen $RUN."

    SCREENS="$RUN/logs/screens"
    MSG="$(ls "$SCREENS"/*-messages.txt 2>/dev/null | head -1)"
    [ -n "$MSG" ] || fail "seed $SEED: the cast left no *-messages.txt screen in $SCREENS."

    # The message box begins at its own header; the ticker above it repeats the
    # last few lines and must not be counted twice. Restrict to the box, drop
    # the sidebar, and collapse whitespace so a wrapped save line still matches.
    BOX="$(awk '/-- Messages --/{f=1;next} f' "$MSG" | cut -c1-64 |
           tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    [ -n "$BOX" ] || fail "seed $SEED: the messages screen held no message box."

    # --- per-cast assertions, from the probe log ---------------------------
    # Split the log into casts at each "cast ..." line. There must be exactly
    # two: one waste burst and one cap burst.
    CASTS=$(grep -c '^cast ' "$PROBE")
    [ "$CASTS" -eq 2 ] ||
        fail "seed $SEED: the probe log has $CASTS cast line(s), expected 2 (one waste burst, one cap burst). specimen $PROBE."

    STRIKES=0
    WASTE_CASTS=0
    BODAK_SKIPC=0
    # Walk each cast's lines in file order. AWK tags each line with its cast
    # number (incremented at a "cast" line) and prints a field-delimited row.
    # A creature name may contain spaces ("crawling claw"), so fields are
    # joined with '|' and read back with IFS='|'.
    PARSED="$(perl -ne '
        if (/^cast .*pool=(\d+)/) { $c++; print "CAST|$c|$1\n"; next }
        if (/^WALK name="([^"]*)" x=(-?\d+) y=(-?\d+) hd=(-?\d+) dist=(-?\d+) remaining=(-?\d+) action=([A-Z-]+)/)
            { print "WALK|$c|$1|$2|$3|$4|$5|$6|$7\n"; next }
        if (/^REJECT-TARGET name="([^"]*)"/) { print "REJECT|$c|$1\n"; next }
    ' "$PROBE")"

    # Pool range, per cast.
    while IFS='|' read -r tag cnum pool; do
        [ "$tag" = CAST ] || continue
        [ -n "$pool" ] || fail "seed $SEED cast $cnum: the probe recorded no pool total. specimen $PROBE."
        [ "$pool" -ge "$POOL_MIN" ] && [ "$pool" -le "$POOL_MAX" ] ||
            fail "seed $SEED cast $cnum: pool=$pool outside $POOL_MIN..$POOL_MAX (11d4). specimen $PROBE."
    done <<< "$PARSED"

    # Walk order and pool arithmetic, per cast.
    for CNUM in 1 2; do
        LINES="$(awk -F'|' -v c="$CNUM" '$1=="WALK" && $2==c' <<< "$PARSED")"
        [ -n "$LINES" ] ||
            fail "seed $SEED cast $CNUM: no WALK lines in the probe log. specimen $PROBE."

        # Read the walk into parallel arrays.
        NAMES=(); HDS=(); DISTS=(); REMS=(); ACTS=()
        while IFS='|' read -r _ _c name x y hd dist rem act; do
            NAMES+=("$name"); HDS+=("$hd"); DISTS+=("$dist")
            REMS+=("$rem"); ACTS+=("$act")
        done <<< "$LINES"

        # Remaining never negative and never below a struck creature's HD.
        last_waste=-1
        for ((i=0; i<${#ACTS[@]}; i++)); do
            [ "${REMS[$i]}" -ge 0 ] ||
                fail "seed $SEED cast $CNUM: remaining=${REMS[$i]} went negative at ${NAMES[$i]}. specimen $PROBE."
            case "${ACTS[$i]}" in
                STRIKE)
                    [ "${HDS[$i]}" -le "${REMS[$i]}" ] ||
                        fail "seed $SEED cast $CNUM: struck ${NAMES[$i]} (${HDS[$i]} HD) with only ${REMS[$i]} in the pool. specimen $PROBE."
                    STRIKES=$((STRIKES+1)) ;;
                WASTE-STOP)
                    [ "${HDS[$i]}" -gt "${REMS[$i]}" ] ||
                        fail "seed $SEED cast $CNUM: WASTE-STOP on ${NAMES[$i]} (${HDS[$i]} HD) but ${REMS[$i]} remained -- the pool could have covered it. specimen $PROBE."
                    [ "$last_waste" -eq -1 ] ||
                        fail "seed $SEED cast $CNUM: a second WASTE-STOP after the walk had already stopped. specimen $PROBE."
                    last_waste=$i ;; 
                SKIP-CAP)
                    [ "${HDS[$i]}" -ge 9 ] ||
                        fail "seed $SEED cast $CNUM: SKIP-CAP on ${NAMES[$i]} with only ${HDS[$i]} HD (cap is 9). specimen $PROBE." ;;
                *)
                    fail "seed $SEED cast $CNUM: unknown action '${ACTS[$i]}' in the probe log. specimen $PROBE." ;;
            esac
        done

        # Nothing may be struck (or walked) after the WASTE-STOP: the walk stops.
        if [ "$last_waste" -ge 0 ]; then
            [ "$last_waste" -eq "$(( ${#ACTS[@]} - 1 ))" ] ||
                fail "seed $SEED cast $CNUM: the walk carried on after WASTE-STOP (later line ${NAMES[$((last_waste+1))]}). specimen $PROBE."
            WASTE_CASTS=$((WASTE_CASTS+1))
        fi

        # Order is by Hit Dice, then by distance to the centre: within one walk
        # the HD sequence never decreases, and among equal HD the distance
        # never decreases.
        for ((i=1; i<${#HDS[@]}; i++)); do
            if [ "${HDS[$i]}" -lt "${HDS[$((i-1))]}" ]; then
                fail "seed $SEED cast $CNUM: walk order broke -- ${NAMES[$i]} (${HDS[$i]} HD) after ${NAMES[$((i-1))]} (${HDS[$((i-1))]} HD). specimen $PROBE."
            fi
            if [ "${HDS[$i]}" -eq "${HDS[$((i-1))]}" ] && [ "${DISTS[$i]}" -lt "${DISTS[$((i-1))]}" ]; then
                fail "seed $SEED cast $CNUM: same-HD tie not ordered nearest-first -- ${NAMES[$i]} d=${DISTS[$i]} after ${NAMES[$((i-1))]} d=${DISTS[$((i-1))]}. specimen $PROBE."
            fi
        done

        # Both claws before any mummy, in the waste burst.
        if [ "$CNUM" -eq 1 ]; then
            saw_mummy=0
            for ((i=0; i<${#NAMES[@]}; i++)); do
                if [ "${NAMES[$i]}" = "mummy" ]; then saw_mummy=1; fi
                if [ "${NAMES[$i]}" = "crawling claw" ] && [ "$saw_mummy" -eq 1 ]; then
                    fail "seed $SEED cast $CNUM: a crawling claw came after a mummy, breaking fewest-HD-first. specimen $PROBE."
                fi
            done
        fi
    done

    [ "$WASTE_CASTS" -ge 1 ] ||
        fail "seed $SEED: no WASTE-STOP in either cast, so R2 was never exercised. specimen $PROBE."

    # --- the bodak, from the probe log -------------------------------------
    BODAK_REJECTS=$(grep -c '^REJECT-TARGET .*name="bodak"' "$PROBE" || true)
    [ "$BODAK_REJECTS" -eq 0 ] ||
        fail "seed $SEED: the bodak appeared as REJECT-TARGET; the spell's undead filter refused it. specimen $PROBE."

    BODAK_STRIKES=$(awk -F'|' '$1=="WALK" && $3=="bodak" && $9=="STRIKE"' <<< "$PARSED" | wc -l | tr -d ' ')
    [ "$BODAK_STRIKES" -eq 0 ] ||
        fail "seed $SEED: the 9-HD bodak was STRIKE-n; the cap did not hold. specimen $PROBE."

    BODAK_SKIPC=$(awk -F'|' '$1=="WALK" && $3=="bodak" && $9=="SKIP-CAP"' <<< "$PARSED" | wc -l | tr -d ' ')
    [ "$BODAK_SKIPC" -ge 1 ] ||
        fail "seed $SEED: the bodak never appeared as SKIP-CAP, so the cap (and the filter's acceptance of it) was never shown. specimen $PROBE."

    # --- save count, from the message log ----------------------------------
    SAVES=$(grep -o 'willsave:' <<< "$BOX" | wc -l | tr -d ' ')
    [ "$SAVES" -ge 1 ] ||
        fail "seed $SEED: no Will save line at all -- the spell never reached its save step. specimen $MSG."
    [ "$SAVES" -eq "$STRIKES" ] ||
        fail "seed $SEED: $SAVES Will save line(s) in the message log but $STRIKES STRIKE line(s) in the probe -- every struck creature rolls exactly one save, saved or not. specimen $MSG."

    PASS_SEEDS="$PASS_SEEDS $SEED"
done

echo "PASS: Undeath to Death pools, caps and wastes its Hit Dice by the SRD rule."
echo "      seeds 1-10, probe logs logs/inc-kgzx/pool/seed-N/logs/hdpoolprobe.log:"
echo "      two casts per seed, each pool within $POOL_MIN..$POOL_MAX;"
echo "      burst one walks fewest-HD/nearest-first, strikes both claws and some"
echo "      mummies, then WASTE-STOPs with nothing struck after it; burst two"
echo "      reaches the 9-HD bodak and SKIPs it without spending; Will save lines"
echo "      equal STRIKE lines."
exit 0
