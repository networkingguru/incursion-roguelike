#!/bin/bash
# gate: live
# Does an attacker WITH the Blind-Fight feat, attacking a victim it cannot
# see, get the 25% miss chance the game's own help promises -- or the 50% the
# buggy HasStati(FT_BLIND_FIGHT) gives when the attacker is not CHARGING?
# (bd inc-4k2)
#
#   tools/check_blind_fight_miss.sh [seeds]   exit 0 all pass, 1 a failed
#                                             assertion, 2 could not measure
#
# THE DEFECT. src/Fight.cpp's vicUnseen miss block reads:
#     if (!random(e.EActor->HasStati(FT_BLIND_FIGHT) ? 4 : 2))
# HasStati() looks up a STATUS effect by number, but FT_BLIND_FIGHT is a FEAT
# number. FT_BLIND_FIGHT == 75 == CHARGING, so only a CHARGING attacker (which
# has nothing to do with the feat) gets the 25% chance, and an attacker who
# actually holds the feat but is not charging keeps 50%. Every other test of
# the feat uses HasFeat (Fight.cpp:4013, 4058, 4520, 4524; Creature.cpp:3471).
# The fix is HasStati -> HasFeat. This check measures the resulting rate.
#
# THE ORACLE is the Combat Options "Avert Eyes" row (src/Player.cpp:996-997),
# which states the rule verbatim: a 50% miss chance in combat, "25% if you have
# the Blind Fighting feat". The probe reads the same predicate the code acts
# on, so the check is grounded in real gameplay, not a copy of the test.
#
# THE PROBE. src/Fight.cpp's BlindFightProbeNote writes logs/blindfight.log,
# off and free unless INCURSION_BLINDFIGHT_PROBE is set; this script sets it.
# One line per attack that reaches the site:
#     turn N: attack actor=<name> victim=<name> vicUnseen=U feat=F charging=C
#             roll=R miss=M
# roll is the size the code chose (4 with the feat, 2 without) and miss is
# whether the "(unable to see)" miss fired. The probe logs only attacks that
# reached the roll, which is the state under test.
#
# THE STAGING (tools/keys/blind-fight-miss.keys): an orc rogue joins a test god
# that grants FT_BLIND_FIGHT (tools/fixtures/blind-fight-god.irh, spliced onto
# a scratch module under logs/, never the tracked lib/), summons a naturally
# invisible poltergeist (SZ_MEDIUM, INV_IMPROVED) one square east, freezes
# monsters so it cannot retaliate or flee, and strikes it 20 times with the
# Combat Options "Attack" verb, which exists for an imperceptible target. The
# attacker is invisible-adjacent but NOT charging, i.e. exactly the case the
# buggy predicate gets wrong.
#
# HOVER IS NOT STAGED. The same HasStati confusion at the aerial flight
# penalty (Fight.cpp, `!e.EActor->HasStati(FT_HOVER)`) is left Traced: it needs
# an aerial attacker whose A_FIRE/A_SPIT attack is rolled while it carries the
# Hover feat or an IMMUNITY status, and no wizard-mode command or key script in
# the harness produces that combination. It is marked in source and in the
# ledger; this check measures only the Blind-Fight half.
#
# THE VERDICT. Count attacks with feat=1 AND charging=0 AND vicUnseen=1. With
# the fix, roll=4 and the miss rate is 25%; unfixed, roll=2 and it is 50%. The
# check fails when the measured rate is nearer 50% than 25% (>= 37.5%), and
# exits 2 when fewer than MIN_COUNT such attacks were measured, so it can never
# pass on too few samples nor on zero.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }

SEEDS="${1:-10}"
MIN_COUNT=100
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }
KEYS=tools/keys/blind-fight-miss.keys
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: $KEYS is not there"; exit 2; }

# Scratch module: a copy of lib/ under logs/, with the test god appended. The
# tracked lib/ is never touched. The god is appended to the END of main.irc,
# which is the append-only position (see tools/fixtures/README.md), so every
# resource id keeps its place.
SCRATCH="$ROOT/logs/check-blind-fight-miss/module"
build_scratch() {
    rm -rf "$SCRATCH"
    mkdir -p "$SCRATCH/mod" "$SCRATCH/save" "$SCRATCH/logs"
    cp -Rf "$ROOT/lib" "$SCRATCH/lib" || { echo "INCONCLUSIVE: could not copy lib/"; exit 2; }
    ln -sfn "$ROOT/inc" "$SCRATCH/inc"
    cat "$ROOT/tools/fixtures/blind-fight-god.irh" >> "$SCRATCH/lib/main.irc"
    INCURSIONPATH="$SCRATCH/" ./incursion-headless -compile main.irc \
        < /dev/null > "$SCRATCH/compile.log" 2>&1
    [ -f "$SCRATCH/mod/Incursion.Mod" ] || {
        echo "INCONCLUSIVE: the scratch module did not compile; see $SCRATCH/compile.log"
        exit 2
    }
}

# Total and miss counters over every trial.
TOTAL=0; MISSES=0; WIRED=0; ROLL4=0; FAILED=0
_token="$$-$(date +%s)"

run_one() { # <seed> <label> -> prints the run directory
    local seed="$1" label="$2" out run
    run="$ROOT/logs/runs/check-blindfight-$_token-$label-seed$seed"
    rm -rf "$run"
    # The scratch module must be what the session loads. tools/headless.sh links
    # the REPOSITORY mod/ into a fresh run directory, but it links with -sfn, so
    # a run directory that ALREADY holds a real mod/Incursion.Mod keeps it (the
    # link lands beside it as mod/mod). Pre-create the directory and copy the
    # scratch module in, exactly as tools/check_heal_maladies.sh relies on.
    mkdir -p "$run/mod"
    cp -f "$SCRATCH/mod/Incursion.Mod" "$run/mod/Incursion.Mod"
    out="$(INCURSION_RUN_DIR="$run" INCURSION_OPTIONS="$OPTIONS" \
            INCURSION_BLINDFIGHT_PROBE=1 \
            tools/headless.sh "$KEYS" "$seed" 2>&1)"
    if grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL' <<< "$out"; then
        FAILED=$((FAILED+1))
    fi
    echo "$run"
}

echo "Blind-Fight unseen-attack miss rate (inc-4k2), $SEEDS seeds"
echo "options: $OPTIONS"
echo "scratch module: $SCRATCH"
echo

build_scratch

for seed in $(seq 1 "$SEEDS"); do
    RUN="$(run_one "$seed" seed)"
    LOG="$RUN/logs/blindfight.log"
    [ -f "$LOG" ] || continue
    read -r tot mis wired r4 < <(awk '
        / attack / && /actor=</ {
            if (/vicUnseen=1/) {
                if (/feat=1/ && /charging=0/) { tot++; if (/miss=1/) mis++; if (/roll=4/) r4++ }
            } else wired++
        }
        END { print tot+0, mis+0, wired+0, r4+0 }
    ' "$LOG")
    TOTAL=$((TOTAL+tot)); MISSES=$((MISSES+mis)); WIRED=$((WIRED+wired)); ROLL4=$((ROLL4+r4))
done

echo "attacks reaching the roll with feat=1, charging=0, vicUnseen=1:  $TOTAL"
echo "  ...of those, \"(unable to see)\" miss fired:                    $MISSES"
echo "  ...of those, the code chose roll=4 (25%):                     $ROLL4"
echo "failed runs: $FAILED"
echo

if [ "$FAILED" -gt 0 ]; then
    echo "INCONCLUSIVE: $FAILED session(s) did not play; see logs/runs/check-blindfight-$_token-*"
    exit 2
fi

if [ "$TOTAL" -lt "$MIN_COUNT" ]; then
    echo "INCONCLUSIVE: only $TOTAL unseen Blind-Fight attacks measured (need >= $MIN_COUNT)"
    exit 2
fi

# Rate nearer 25% (fixed) than 50% (unfixed). The midpoint is 37.5%; compare
# with integer arithmetic to avoid a float.
#   100*MISSES/TOTAL < 37.5  <=>  2*100*MISSES < 75*TOTAL
if [ $((200 * MISSES)) -lt $((75 * TOTAL)) ]; then
    echo "PASS: $MISSES/$TOTAL unseen attacks missed -- nearer 25%, as the feat promises"
    exit 0
fi

echo "FAIL: $MISSES/$TOTAL unseen attacks missed -- nearer 50% than the 25%"
echo "      Blind-Fight promises. The feat is being looked up as a status"
echo "      (FT_BLIND_FIGHT == CHARGING == 75), so a non-charging holder keeps"
echo "      the 50% roll. Fix src/Fight.cpp's HasStati(FT_BLIND_FIGHT) -> HasFeat."
exit 1
