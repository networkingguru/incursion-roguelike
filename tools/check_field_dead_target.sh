#!/bin/bash
# gate: live
# inc-8vxk6: a spell whose creature target dies in the caster's attack of
# opportunity does not run: Magic::AField is not entered, no field is made, and
# Map::Update is not handed (-1,-1).
#
# fact: character -- fixture orc-barbarian-seed1-opt0822, INCURSION_LOAD; the probe uses it only as a map anchor
# fact: caster and target -- the probe places two kobolds near the player and gives the caster 100 mana (INCURSION_FIELD_DEAD_TARGET_PROBE); the check requires hook=1 alive=1 dead=1, else it fails
# fact: spell -- Call Light (lib/pspells.irh), an AR_FIELD effect, invoked through ThrowEff(EV_INVOKE) so it reaches Creature::Invoke
# fact: target death -- FieldDeadTargetKill kills the target with 10000 blunt damage right after ProvokeAoO, so no attack-of-opportunity roll decides it
# fact: settings -- tools/fixtures/options-2026-08-22.dat, INCURSION_OPTIONS
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/field-dead-target.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-field_dead_target"
out="$(INCURSION_FIELD_DEAD_TARGET_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run_status=$?

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "$out" | tail -20
    echo "FAIL: no $log. The probe never wrote anything."
    exit 1
fi

line="$(grep 'FIELD_DEAD_TARGET_PROBE' "$log")"
if [ -z "$line" ]; then
    echo "FAIL: $log has no FIELD_DEAD_TARGET_PROBE line."
    exit 1
fi
echo "$line"
echo "Specimen: $log"
if [ "$(wc -l <<< "$line")" -ne 1 ]; then
    echo "FAIL: expected exactly one FIELD_DEAD_TARGET_PROBE line."
    exit 1
fi
if grep -q 'InBounds' "$log"; then
    grep 'InBounds' "$log" | head -3
    echo "FAIL: errors.log holds an InBounds assert."
    exit 1
fi
if [ "$run_status" -ne 0 ]; then
    echo "$out" | tail -20
    echo "FAIL: headless exited $run_status"
    exit 1
fi
if ! grep -qE 'FIELD_DEAD_TARGET_PROBE hook=1 alive=1 dead=1 ' <<< "$line"; then
    echo "FAIL: staging did not happen (need hook=1 alive=1 dead=1)."
    exit 1
fi
if ! grep -qE 'afield=0 ' <<< "$line"; then
    echo "FAIL: Magic::AField ran on a target that was already dead."
    exit 1
fi
b="$(sed -E 's/.*fieldsbefore=([0-9]+).*/\1/' <<< "$line")"
a="$(sed -E 's/.*fieldsafter=([0-9]+).*/\1/' <<< "$line")"
if [ "$a" != "$b" ]; then
    echo "FAIL: the cast made a field (before=$b after=$a)."
    exit 1
fi
echo "PASS: a spell whose target died in the attack of opportunity did not enter AField or make a field."
