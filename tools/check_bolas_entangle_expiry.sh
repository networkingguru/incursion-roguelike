#!/bin/bash
# Does an entangling thrown weapon (bolas) let go by itself? Bead inc-9smo.
#
# THE DEFECT. src/Fight.cpp Weapon::QualityDmg grants STUCK from an entangling
# weapon with DAMAGE(..., AD_STUK, -1, ...). The -1 reaches the AD_STUK arm as
# e.vDmg and becomes the STUCK stati Duration. Thing::UpdateStati only counts
# down a Duration above zero, so the stati never expires. The only exit is the
# escape check in src/Move.cpp (Escape Artist DC 20 / Strength DC 25). A
# creature that makes no escape check stays stuck for ever.
#
# THE ORACLE is the victim's own status list, read through wizard "Examine
# Nearby Things" (tools/keys/bolas-entangle-expiry.keys). Right after the throw
# the list must hold "STUCK from SS_ATTK ... [Dur -1]" (red-now) or a positive
# duration (after the fix). After 150 waited turns, about 2400 game ticks, the
# STUCK line MUST be gone. The victim is frozen (Freeze Monsters), so it makes
# no escape check: nothing but expiry can remove STUCK. A control stati on the
# same victim (TRIED) is shown to expire in the same wait, so a frozen victim
# does tick its stati.
#
# RED BEFORE, GREEN AFTER. Before the fix the STUCK line is still there, with
# Dur -1. After the fix (duration Dice::Roll(2,4)) it is gone within the wait.
#
# CAN'T-TELL IS NOT PASS. A run counts only if the throw printed "entangles the
# bugbear" AND the "before" list holds STUCK. The entangle needs a hit and a
# failed Reflex save, so the script runs seeds 1..SEEDS (default 20) and reports
# the entangle rate. No entangled run at all, or a victim that died, is exit 2.
#
# Usage: tools/check_bolas_entangle_expiry.sh [SEEDS]
#        (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

SEEDS="${1:-20}"
KEYS=tools/keys/bolas-entangle-expiry.keys
LOAD=tools/fixtures/chars/kobold-rogue-seed1.sav
OPTS=tools/fixtures/options-2026-08-22.dat

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$LOAD" ] && [ -f "$OPTS" ] || { echo "INCONCLUSIVE: fixture missing"; exit 2; }

ran=0; hit=0; entangled=0; fail=0; pass=0; skipped=0
for seed in $(seq 1 "$SEEDS"); do
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-bolas-expiry-s$seed"
    out="$(INCURSION_RUN_DIR="$RUN_DIR" INCURSION_LOAD="$LOAD" INCURSION_OPTIONS="$OPTS" \
           INCURSION_MAP_AUDIT=0 tools/headless.sh "$KEYS" "$seed" 2>&1)"
    S="$RUN_DIR/logs/screens"
    ran=$((ran + 1))
    # A run that never reached its dumps (the bugbear died, so the examine
    # list has no "bugbear (class") measured nothing.
    if ! ls "$S"/*-after.txt >/dev/null 2>&1; then
        skipped=$((skipped + 1)); continue
    fi
    thrown="$(cat "$S"/*-thrown.txt)"
    echo "$thrown" | grep -q "hitting the" && hit=$((hit + 1))
    echo "$thrown" | grep -q "entangles the bugbear" || continue
    entangled=$((entangled + 1))
    before="$(cat "$S"/*-before.txt)"
    after="$(cat "$S"/*-after.txt)"
    if ! echo "$before" | grep -q "STUCK from SS_ATTK"; then
        echo "seed $seed: INCONCLUSIVE: entangle message seen but no STUCK on the victim"
        skipped=$((skipped + 1)); continue
    fi
    if grep -qhE "Escape Artist Check:|Strength Check:" "$S"/*; then
        echo "seed $seed: INCONCLUSIVE: an escape check was rolled, so expiry is not isolated"
        skipped=$((skipped + 1)); continue
    fi
    t0="$(echo "$before" | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="turn") print $(i+1)}')"
    t1="$(echo "$after"  | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="turn") print $(i+1)}')"
    # Control: a different timed stati on the same victim must have ticked.
    if echo "$before" | grep -q "TRIED from SS_MISC" && echo "$after" | grep -q "TRIED from SS_MISC"; then
        echo "seed $seed: INCONCLUSIVE: control stati TRIED did not expire, so the wait did not tick"
        skipped=$((skipped + 1)); continue
    fi
    line="$(echo "$before" | grep "STUCK from SS_ATTK" | sed 's/ *|.*//')"
    if echo "$after" | grep -q "STUCK from SS_ATTK"; then
        left="$(echo "$after" | grep "STUCK from SS_ATTK" | sed 's/ *|.*//')"
        echo "seed $seed: FAIL: still stuck after $((t1 - t0)) ticks"
        echo "      entangled: $line"
        echo "      later:     $left"
        fail=$((fail + 1))
    else
        echo "seed $seed: ok: STUCK gone after at most $((t1 - t0)) ticks ($line)"
        pass=$((pass + 1))
    fi
done

echo "runs $ran, hit $hit, entangled $entangled (rate $entangled/$ran), skipped $skipped," \
     "stuck-forever $fail, expired $pass"
if [ "$entangled" = 0 ] || [ $((fail + pass)) = 0 ]; then
    echo "INCONCLUSIVE: no run showed a clean entangle to judge."
    exit 2
fi
if [ "$fail" -gt 0 ]; then
    echo "FAIL: bolas STUCK never expires on its own (Duration -1 is never counted down)."
    exit 1
fi
echo "PASS: bolas STUCK expired by itself in every entangled run."
exit 0
