#!/bin/bash
# gate: live
# inc-q33r: AD_STUN stun duration, measured live.
# Loaded priest, forced natural-1 saves, one kobold on an open square adjacent
# to the player. ThrowDmg(EV_DAMAGE, AD_STUN, amount, ...) with EActor=player
# and EVictim=kobold reaches the AD_STUN branch (EActor=p[0], EVictim=p[1];
# inc/Events.h). For each amount in {3, 9} the stun must last exactly that
# many rounds and its cause must be SS_ATTK. Before the fix the Duration and
# Cause arguments were swapped, so every stun lasted SS_ATTK (6) and carried
# the rolled amount as its cause. FAIL, INCONCLUSIVE or missing results exit
# nonzero.
# Usage: tools/check_stun_duration.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/bane-radius.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-stun-dur"
INCURSION_STUN_DUR_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. Is StunDurProbe still called from Game::Play()?"
    exit 1
fi

lines="$(grep 'STUN_DUR_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no STUN_DUR_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"

if grep -qE 'STUN_DUR_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
n="$(grep -c 'STUN_DUR_PROBE: amount=' <<< "$lines")"
if [ "$n" -lt 2 ]; then
    echo "FAIL: measured $n amount lines, want at least 2."
    exit 1
fi
if ! grep -q 'STUN_DUR_PROBE: PASS' <<< "$lines"; then
    echo "FAIL: missing PASS result."
    exit 1
fi

echo "PASS: AD_STUN stun lasts the rolled amount with cause SS_ATTK."
