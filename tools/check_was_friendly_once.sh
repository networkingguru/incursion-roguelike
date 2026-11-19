#!/bin/bash
# gate: live
# inc-n3eni: a creature holds at most one WAS_FRIENDLY per attacker, even when
# its target table is full and addTarget refuses the attacker on every hit.
#
# fact: character -- fixture orc-barbarian-seed1-opt0822, INCURSION_LOAD; the probe uses it only as a map anchor
# fact: victim, attacker and filler creatures -- the probe places three kobolds beside the player (INCURSION_WAS_FRIENDLY_PROBE)
# fact: attacker neutral to the victim -- the probe gives the attacker NEUTRAL_TO(any), so ItHitMe reaches the grant
# fact: victim's target table -- the probe fills all 32 slots with priority-30 enemies; the check requires tcount=32 and addfail=yes, else it fails
# fact: hits -- the probe calls ItHitMe 20 times with damage 1
# fact: settings -- tools/fixtures/options-2026-08-22.dat, INCURSION_OPTIONS
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/was-friendly.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-was_friendly"
out="$(INCURSION_WAS_FRIENDLY_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run_status=$?

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "$out" | tail -20
    echo "FAIL: no $log. The probe never wrote anything."
    exit 1
fi

line="$(grep 'WAS_FRIENDLY_PROBE' "$log")"
if [ -z "$line" ]; then
    echo "FAIL: $log has no WAS_FRIENDLY_PROBE line."
    exit 1
fi
echo "$line"
echo "Specimen: $log"
if [ "$(wc -l <<< "$line")" -ne 1 ]; then
    echo "FAIL: expected exactly one WAS_FRIENDLY_PROBE line."
    exit 1
fi
if [ "$run_status" -ne 0 ]; then
    echo "$out" | tail -20
    echo "FAIL: headless exited $run_status"
    exit 1
fi
if ! grep -qE 'WAS_FRIENDLY_PROBE count=[0-9]+ tcount=32 addfail=yes recorded=no$' <<< "$line"; then
    echo "FAIL: staging did not happen (need tcount=32 addfail=yes recorded=no)."
    exit 1
fi
if ! grep -qE 'WAS_FRIENDLY_PROBE count=1 ' <<< "$line"; then
    echo "FAIL: the victim does not hold exactly one WAS_FRIENDLY for the attacker."
    exit 1
fi
echo "PASS: 20 hits on a creature with a full target table grant one WAS_FRIENDLY."
