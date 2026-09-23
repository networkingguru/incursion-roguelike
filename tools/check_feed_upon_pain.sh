#!/bin/bash
# gate: live
# Assert the Feed upon Pain running tally and level-stacking for bead
# inc-akac.
#
#   tools/check_feed_upon_pain.sh [priest-trials] [giant-trials]
#                                            exit 0 all pass, 1 a failed
#                                            assertion, 2 a case measured
#                                            nothing
#
# Bead inc-akac. src/Creature.cpp's POST(EV_STRIKE) handler for
# CA_FEED_UPON_PAIN used to judge each strike alone (needing MORE than 10
# combined damage per blow), drop any remainder, and ignore the ability's
# level. The fix replaces it with a running tally, stored in the striker's
# own PAIN_TALLY status (inc/Defines.h): every landed, damaging strike adds
# dmg * level to the tally; every full 10 in the tally heals that many hit
# points; the 0-9 remainder carries to the next strike.
#
# INCURSION_OPTIONS overrides the settings fixture; the default is
# tools/fixtures/options-sneak-invis.dat (tools/gates/Options.Dat with
# Automatic Hide in Shadows forced off -- irrelevant to this check, but it
# is a live-combat fixture already proven to carry Cheat Death, and reusing
# a described, committed fixture beats freezing a new one for no reason).
#
# THE PROBE. src/Creature.cpp's PainProbeNote writes logs/pain.log in a run
# directory: one line per landed, damaging strike by a creature that has
# CA_FEED_UPON_PAIN, naming the actor, the ability level, the strike's own
# damage, the tally before and after, and the hit points actually healed
# (capped by max HP, so it can read 0 even when the tally crossed a 10).
# Set INCURSION_PAIN_PROBE=1; this script sets it. Each run gets a FRESH
# directory (the probe appends), so two invocations tally the same counts.
#
# THE TWO CASES.
#
#   PRIEST (level 1, RED case). tools/keys/pain-experiment.keys builds an
#   orc priest of Khasrach with the Pain domain, then empties the priest's
#   weapon hand so AttackMode() falls back to bare-fisted brawling (Punch
#   1d3+3, always <= 10 -- see the key script's own header for why a
#   longspear cannot be used for this). Every strike this priest lands is
#   individually at or under the OLD code's ">10 combined damage" gate, so
#   the old code would produce ZERO probe lines here: the whole `if` this
#   probe lives inside never triggers below 11 damage. Counting these lines
#   at all is therefore already RED-on-the-old-code evidence; this script
#   additionally recomputes the tally arithmetic from each line and asserts
#   it matches the new formula exactly.
#
#   FROST GIANT (level 6). tools/keys/pain-giant.keys summons a frost giant
#   (lib/mon2.irh, ABILITY(CA_FEED_UPON_PAIN,6)) next to a fresh rogue and
#   waits for it to land a blow. A giant's blow is well above 10 damage, so
#   the old code would still heal something here -- but only dmg/10,
#   dropping the level entirely (a level-6 source is supposed to heal 6 HP
#   per 10 damage). This script asserts the probe's own level field reads 6
#   on every line, and that the tally arithmetic uses that level.
#
# A case that produces no probe line at all exits 2: nothing was measured.
# Every asserted count must reach its MIN, or exit 1 -- a handful of trials
# is not enough seeds to trust as a rate.
#
# Commands (Brian's brief, docs/VERIFICATION.md):
#   BACKEND=posix ./build_macos.sh
#   tools/check_feed_upon_pain.sh            # green on the fixed build
#   tools/check_feed_upon_pain.sh            # second run: same shape
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }

PRIEST_TRIALS="${1:-12}"
GIANT_TRIALS="${2:-8}"
MIN_LOW=10      # min priest strikes, each <= 10 damage, across all trials
MIN_HEAL=1      # min actual heal>0 events among those strikes
MIN_GIANT=5     # min frost-giant strikes across all trials
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-sneak-invis.dat}"
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }

PRIEST_KEY=tools/keys/pain-experiment.keys
GIANT_KEY=tools/keys/pain-giant.keys

TOKEN="${INCURSION_CHECK_TOKEN:-$$-$(date +%s)}"
RUN_SEQ=0
FAILED=0

# Fresh directory per trial, same convention as tools/check_sneak_invis.sh.
run_one() { # <keyscript> <seed> <label> -> prints the run directory
    local keys="$1" seed="$2" label="$3" out run
    RUN_SEQ=$((RUN_SEQ+1))
    local RUN_DIR="$ROOT/logs/runs/check-feed-pain-$TOKEN-$(printf '%02d' "$RUN_SEQ")-$label-seed$seed"
    rm -rf "$RUN_DIR"
    export INCURSION_RUN_DIR="$RUN_DIR"
    out="$(INCURSION_OPTIONS="$OPTIONS" INCURSION_PAIN_PROBE=1 \
            tools/headless.sh "$keys" "$seed" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if grep -qE 'WATCHDOG|FATAL' <<< "$out"; then
        FAILED=$((FAILED+1))
    fi
    echo "$run"
}

echo "Feed upon Pain running tally + level stacking (inc-akac)"
echo "priest trials: $PRIEST_TRIALS, giant trials: $GIANT_TRIALS"
echo "options: $OPTIONS"
echo

# ---------------------------------------------------------------- priest
TOTAL=0; LOW=0; HEAL_POS=0; MATH_BAD=0; PRIEST_LINES=""
for seed in $(seq 1 "$PRIEST_TRIALS"); do
    RUN="$(run_one "$PRIEST_KEY" "$seed" priest)"
    LOG="$RUN/logs/pain.log"
    [ -f "$LOG" ] || continue
    PRIEST_LINES="$PRIEST_LINES
$(cat "$LOG")"
done

# Recompute each line's tally arithmetic. Every actor here has the ability
# only from the Pain domain (level 1), and the probe only ever fires for a
# creature that HasAbility(CA_FEED_UPON_PAIN), so every line belongs to the
# priest -- the bear it fights has no such ability and is never logged.
read -r TOTAL LOW HEAL_POS MATH_BAD < <(echo "$PRIEST_LINES" | awk '
    /^turn/ {
        n = 0
        for (i = 1; i <= NF; i++) {
            split($i, kv, "=")
            v[kv[1]] = kv[2]
        }
        total++
        dmg = v["dmg"] + 0; lvl = v["level"] + 0
        tb = v["tally_before"] + 0; ta = v["tally_after"] + 0
        healed = v["healed"] + 0
        expected_ta = (tb + dmg * lvl) % 10
        if (ta != expected_ta) bad++
        if (dmg <= 10) low++
        if (healed > 0) healpos++
    }
    END { print total+0, low+0, healpos+0, bad+0 }
')

echo "PRIEST (level 1, brawling, every blow <= 10 damage):"
echo "     total probe lines:                                        $TOTAL"
echo "     of those, dmg <= 10 (the RED-vs-old-code subset):          $LOW"
echo "     of those, an actual heal (healed > 0) happened:            $HEAL_POS"
echo "     tally-arithmetic mismatches (must be 0):                   $MATH_BAD"
echo

# ---------------------------------------------------------------- giant
GIANT_LINES=""
for seed in $(seq 1 "$GIANT_TRIALS"); do
    RUN="$(run_one "$GIANT_KEY" "$seed" giant)"
    LOG="$RUN/logs/pain.log"
    [ -f "$LOG" ] || continue
    GIANT_LINES="$GIANT_LINES
$(grep 'actor=<frost giant>' "$LOG" 2>/dev/null)"
done

read -r GTOTAL GBAD GLVLBAD < <(echo "$GIANT_LINES" | awk '
    /^turn/ {
        for (i = 1; i <= NF; i++) {
            split($i, kv, "=")
            v[kv[1]] = kv[2]
        }
        total++
        dmg = v["dmg"] + 0; lvl = v["level"] + 0
        tb = v["tally_before"] + 0; ta = v["tally_after"] + 0
        expected_ta = (tb + dmg * lvl) % 10
        if (ta != expected_ta) bad++
        if (lvl != 6) lvlbad++
    }
    END { print total+0, bad+0, lvlbad+0 }
')

echo "FROST GIANT (level 6):"
echo "     total probe lines:                                        $GTOTAL"
echo "     tally-arithmetic mismatches (must be 0):                   $GBAD"
echo "     lines whose level field is not 6 (must be 0):              $GLVLBAD"
echo
echo "failed runs (WATCHDOG/FATAL): $FAILED"
echo

# ---------------------------------------------------------------- assertions
if [ "$TOTAL" -eq 0 ] && [ "$GTOTAL" -eq 0 ]; then
    echo "FAIL: nothing was measured; neither case produced a probe line"
    exit 2
fi
if [ "$TOTAL" -eq 0 ]; then
    echo "FAIL: the priest case saw no probe line at all"
    exit 2
fi
if [ "$GTOTAL" -eq 0 ]; then
    echo "FAIL: the frost giant case saw no probe line at all"
    exit 2
fi

RC=0
fail() { echo "FAIL: $*"; RC=1; }

if [ "$LOW" -lt "$MIN_LOW" ]; then
    fail "priest case measured only $LOW strikes at <= 10 damage (need >= $MIN_LOW)"
fi
if [ "$HEAL_POS" -lt "$MIN_HEAL" ]; then
    fail "priest case measured only $HEAL_POS actual heal(s) from low-damage strikes (need >= $MIN_HEAL)"
fi
if [ "$MATH_BAD" -ne 0 ]; then
    fail "priest case: $MATH_BAD probe line(s) failed the tally-arithmetic check"
fi
if [ "$GTOTAL" -lt "$MIN_GIANT" ]; then
    fail "frost giant case measured only $GTOTAL strikes (need >= $MIN_GIANT)"
fi
if [ "$GBAD" -ne 0 ]; then
    fail "frost giant case: $GBAD probe line(s) failed the tally-arithmetic check"
fi
if [ "$GLVLBAD" -ne 0 ]; then
    fail "frost giant case: $GLVLBAD probe line(s) read a level other than 6"
fi

if [ "$RC" -ne 0 ]; then
    echo
    echo "FAIL: one or more Feed upon Pain assertions failed"
    exit 1
fi
echo "PASS: Feed upon Pain running tally and level stacking both hold"
exit 0
