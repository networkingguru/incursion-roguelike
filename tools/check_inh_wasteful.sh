#!/bin/bash
# gate: live
# Assert that Creature::GainInherentBonus wastes a tome when the inherent
# total is AT OR ABOVE the cap, not only when it is exactly equal. bd inc-bsqm.
#
# THE DEFECT. src/Creature.cpp's GainInherentBonus computes
#   MaxBonus = 5 + AbilityLevel(CA_INHERANT_POTENTIAL)
#   CurrBonus = SumStatiMag(ADJUST_INH, at)
# and returns early, printing "You feel a profound sense of wastefulness.",
# only when CurrBonus == MaxBonus. A character already ABOVE the cap --
# reachable in play when a polymorphed shambling mound's electricity handler
# (lib/mon3.irh:2102) adds an uncapped +1d4 ADJUST_INH on top of a cap already
# filled by tomes -- misses that test: the call falls through, prints a false
# "you feel <attr>" line and mutates the bonus.
#
# THE ORACLE. The probe in src/Creature.cpp (INCURSION_INH_PROBE=1) arms the
# attribute on the player's FIRST GainInherentBonus call, calls it once, and
# writes to logs/inh.log a line:
#   inh: at=1 max=5 curr=6 message=gain after=6
# where message is "wasteful" when the early return was taken and "gain"
# otherwise, and after is the summed ADJUST_INH for that attribute when the
# call returned. The correct behaviour is message=wasteful and after==curr
# (no change); the bug shows message=gain.
#
# THE RUN. It LOADS the frozen orc barbarian (INCURSION_LOAD) and
# tools/keys/inh-wasteful.keys takes a +5 DEX tome from wizard Item Acquisition
# and reads it. That read is the run's first GainInherentBonus call, so the
# probe arms A_DEX (which the barbarian's creation never touched) just before
# it. No character generation runs, so no seed decides the outcome.
#
# RED on current code: message reads "gain". GREEN once the test is >=.
#
# The probe's default arm puts curr = max + 1. INCURSION_INH_PROBE_OFFSET=-1
# arms the permanent grant one point UNDER the cap instead, so the same script
# also proves the fix did not over-refuse a legal tome: that run must read
# message=gain and after > curr (the bonus rose).
#
# A run that cannot set the state up (no log, no reading, wrong attribute, the
# key script lost on a screen, curr on the wrong side of max) is INCONCLUSIVE.
#
# fact: character -- fixture orc-barbarian-seed1-opt0818 (INCURSION_LOAD), no chargen
# fact: the tome and its +5 -- wizard Item Acquisition, chosen by name
# fact: over-cap and under-cap starting total -- INCURSION_INH_PROBE (+ _OFFSET=-1), guarded by curr vs max
# fact: the result -- the probe's logs/inh.log line, not screen text
# fact: the attribute read -- at=1 (A_DEX), asserted
#
# Usage: tools/check_inh_wasteful.sh     (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

SEED=1
KEYS=tools/keys/inh-wasteful.keys
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-18.dat}"
FIXTURE=tools/fixtures/chars/orc-barbarian-seed1-opt0818.sav
[ -f "$OPTIONS" ] || {
    echo "INCONCLUSIVE: settings file $OPTIONS is not there."
    exit 2
}
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: key script $KEYS is not there."; exit 2; }
[ -f "$FIXTURE" ] || { echo "INCONCLUSIVE: character fixture $FIXTURE is not there."; exit 2; }

TOKEN="${INCURSION_CHECK_TOKEN:-$$-$(date +%s)}"

# run_probe <tag> <offset>  -- offset empty uses the default over-cap (+1) arm.
# Writes the single 'inh:' line to stdout and the specimen path to stderr, so
# the caller can print both. Returns the line on stdout.
run_probe() {
    local tag=$1 offset=$2 RUN OUT LOG LINE
    RUN="$ROOT/logs/runs/check-inh-wasteful-$TOKEN-$tag-seed$SEED"
    rm -rf "$RUN"
    local -a probe_env=(INCURSION_INH_PROBE=1)
    [ -n "$offset" ] && probe_env+=("INCURSION_INH_PROBE_OFFSET=$offset")
    OUT="$(env INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTIONS" \
           INCURSION_LOAD="$FIXTURE" \
           "${probe_env[@]}" tools/headless.sh "$KEYS" "$SEED" 2>&1)"
    RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
    LOG="$RUN/logs/inh.log"
    if grep -q "the key script looked for something" <<< "$OUT"; then
        echo "INCONCLUSIVE: the key script stopped on a screen it did not expect." >&2
        echo "$OUT" | tail -12 >&2
        return 2
    fi
    if [ ! -f "$LOG" ]; then
        echo "INCONCLUSIVE: the probe never wrote $LOG, so nothing was measured." >&2
        echo "$OUT" | tail -12 >&2
        return 2
    fi
    LINE="$(grep -m1 '^inh:' "$LOG")"
    if [ -z "$LINE" ]; then
        echo "INCONCLUSIVE: $LOG holds no 'inh:' reading, so nothing was measured." >&2
        echo "      $(head -3 "$LOG")" >&2
        return 2
    fi
    echo "specimen: $LOG" >&2
    printf '%s\n' "$LINE"
}

parse_line() {
    AT="" MSG=""
    eval "$(echo "$1" | sed -n 's/^inh: at=\([0-9]*\) max=\([0-9-]*\) curr=\([0-9-]*\) message=\([a-z]*\) after=\([0-9-]*\)$/AT=\1 MAX=\2 CURR=\3 MSG=\4 AFTER=\5/p')"
    if [ -z "${AT:-}" ] || [ -z "${MSG:-}" ]; then
        echo "INCONCLUSIVE: could not parse the probe reading:"
        echo "      $1"
        return 2
    fi
    if [ "$AT" != "1" ]; then
        echo "INCONCLUSIVE: the probe armed attribute $AT, not 1 (A_DEX); the tome"
        echo "              read was not the run's first GainInherentBonus call."
        return 2
    fi
}

RC=0
fail() { echo "FAIL: $*"; RC=1; }

# --- Case 1: the over-cap tome (the defect). Default arm puts curr = max + 1.
LINE="$(run_probe overcap "")" || exit 2
parse_line "$LINE" || exit 2
echo "probe (over cap): $LINE"

# Guard: the probe must actually have put the character ABOVE the cap. If it
# did not, the assertion below would pass for the wrong reason.
if [ "$CURR" -le "$MAX" ]; then
    echo "INCONCLUSIVE: curr=$CURR is not above max=$MAX, so the over-cap state"
    echo "              was never set up; this run measured nothing."
    exit 2
fi
echo "  ok: curr=$CURR is above max=$MAX, so the over-cap state is real"

if [ "$MSG" != "wasteful" ]; then
    fail "the over-cap call printed '$MSG', not 'wasteful': the tome was not"
    echo "      refused. GainInherentBonus's == test missed an over-cap total."
fi

if [ "$AFTER" -ne "$CURR" ]; then
    fail "the bonus changed from $CURR to $AFTER on an over-cap call; a wasted"
    echo "      tome must leave it alone."
fi

# --- Case 2: a normal tome read BELOW the cap must still raise the bonus.
# INCURSION_INH_PROBE_OFFSET=-1 arms the permanent grant one point under the
# cap, so GainInherentBonus must take the gain branch and the total must rise.
LINE="$(run_probe undercap -1)" || exit 2
parse_line "$LINE" || exit 2
echo "probe (under cap): $LINE"

if [ "$CURR" -ge "$MAX" ]; then
    echo "INCONCLUSIVE: curr=$CURR is not below max=$MAX, so the under-cap case"
    echo "              was never set up; the non-regression proves nothing."
    exit 2
fi

if [ "$MSG" != "gain" ]; then
    fail "an under-cap read printed '$MSG', not 'gain': the fix over-refused a"
    echo "      legal tome."
fi

if [ "$AFTER" -le "$CURR" ]; then
    fail "an under-cap read left the bonus at $AFTER (was $CURR); a legal tome"
    echo "      must still raise it."
fi

if [ "$RC" -ne 0 ]; then
    echo
    echo "FAIL: GainInherentBonus did not waste the over-cap tome (inc-bsqm)"
    exit 1
fi
echo "PASS: the over-cap tome was wasted, and an under-cap tome still raised"
echo "      the bonus"
exit 0
