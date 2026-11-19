#!/bin/bash
# gate: live
# inc-h5v6o: a ridden mount gets the field events its rider gets from
# Map::NewField, Map::MoveField and Map::RemoveField, so it holds one field
# entry while the field covers the rider and none after.
#
# fact: character -- fixture orc-barbarian-seed1-opt0822, INCURSION_LOAD; the probe uses it only as a map anchor
# fact: rider, mount and field creator -- the probe places two kobolds and a pony near the player and mounts one kobold (INCURSION_MOUNT_FIELD_PROBE); the check requires mounted=yes and onlist=no, else it fails
# fact: field -- the probe creates a Globe of Shadow field made by the third creature, so neither rider nor mount is its creator
# fact: stati per entry -- Globe of Shadow has two effect segments (SKILL_BONUS, MISS_CHANCE), so one field entry grants two stati; the check requires afternew=2, else it fails (lib/wspells.irh)
# fact: moves -- each of 20 cycles the probe walks the rider into a one-square field with Thing::Move and moves the field off with Map::MoveField, then creates and removes the field over the rider
# fact: settings -- tools/fixtures/options-2026-08-22.dat, INCURSION_OPTIONS
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/mount-field.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-mount_field"
out="$(INCURSION_MOUNT_FIELD_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run_status=$?

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "$out" | tail -20
    echo "FAIL: no $log. The probe never wrote anything."
    exit 1
fi

line="$(grep 'MOUNT_FIELD_PROBE' "$log")"
if [ -z "$line" ]; then
    echo "FAIL: $log has no MOUNT_FIELD_PROBE line."
    exit 1
fi
echo "$line"
echo "Specimen: $log"
if [ "$(wc -l <<< "$line")" -ne 1 ]; then
    echo "FAIL: expected exactly one MOUNT_FIELD_PROBE line."
    exit 1
fi
if [ "$run_status" -ne 0 ]; then
    echo "$out" | tail -20
    echo "FAIL: headless exited $run_status"
    exit 1
fi
if ! grep -qE 'MOUNT_FIELD_PROBE mounted=yes onlist=no ' <<< "$line"; then
    echo "FAIL: staging did not happen (need mounted=yes onlist=no)."
    exit 1
fi
if ! grep -qE 'maxcount=2 afterleave=0 afternew=2 afterremove=0$' <<< "$line"; then
    echo "FAIL: the mount does not hold exactly one field entry (two stati) while the field covers its rider and none after (a count above 2 or left after the field moves off is the leak)."
    exit 1
fi
echo "PASS: a ridden mount gets one field entry (two stati) on entry and none after leaving or removal."
