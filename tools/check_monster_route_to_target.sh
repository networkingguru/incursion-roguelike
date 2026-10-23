#!/usr/bin/env bash
# gate: live
# inc-rabe: SmartDirTo must route to a perceived hostile creature behind a wall.
# fact: key bindings and overview entry -- options-2026-08-22.dat and monster-route-check.keys
# fact: player identity and initial world -- fixture kobold-rogue-seed1.sav
# fact: monster identity, position and no ambient creatures -- RouteProbe staging
# fact: player position and survival -- RouteProbe staging (10,10; 10000 HP)
# fact: known floor, size-compatible region and U corridor -- RouteProbe staging
# fact: no line of fire and straight step blocked -- RouteProbe U corridor staging
# fact: mutual hostility -- RouteProbe TargetEnemy entries for both actors
# fact: perception through wall -- RouteProbe CA_TELEPATHY=30, removes player NONDETECTION/HIDING
# fact: route option enabled -- RouteProbe sets player Options[OPT_MON_DJIKSTRA]=1
# fact: nonblocking message display -- RouteProbe sets OPT_AUTOMORE=1
# fact: route result before AI decisions -- RouteProbe calls SmartDirTo once at staging
# fact: expected first step, straight direction and CENTER -- RouteProbe geometry/Dir enum
# Usage: tools/check_monster_route_to_target.sh [seed]
# INCURSION_ROUTE_PROBE=missing exercises the unmeasurable setup path.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
mkdir -p logs/runs
run=$(mktemp -d "$PWD/logs/runs/monster-route-check.XXXXXX") || exit 2
INCURSION_ROUTE_PROBE="${INCURSION_ROUTE_PROBE:-1}" INCURSION_RUN_DIR="$run" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/kobold-rogue-seed1.sav \
    tools/headless.sh tools/keys/monster-route-check.keys "${1:-3}" > "$run/harness.txt" 2>&1
rc=$?
python3 - "$run" "$rc" <<'PY'
import pathlib, sys
run = pathlib.Path(sys.argv[1])
def unmeasured(reason):
    print(f'UNMEASURED: {reason}; specimens={run}'); sys.exit(2)
if sys.argv[2] != '0': unmeasured('headless exit ' + sys.argv[2])
log = run / 'logs/routeprobe.log'
if not log.exists(): unmeasured('no setup log')
lines = [x for x in log.read_text().splitlines() if x.startswith('setup ')]
if len(lines) != 1: unmeasured('expected exactly one setup call')
print(lines[0])
f = dict(x.split('=', 1) for x in lines[0].split()[1:])
if f.get('missing') != '0': unmeasured('no staged monster')
try:
    if (f['mon'], f['player']) != ('14,10', '10,10'): unmeasured('positions')
    if (int(f['lof']) or not int(f['perceives']) or f['hostile'] != '1'
        or f['opt'] != '1' or f['telepathy'] != '30' or f['blocked'] != '1'):
        unmeasured('setup preconditions')
    direction, center, straight, expected = (int(f[k]) for k in ('dir','center','straight','expected'))
except (KeyError, ValueError): unmeasured('malformed setup line')
ok = direction == expected and direction not in (center, straight)
print(f'{"PASS" if ok else "FAIL"}: dir={direction}, expected={expected}, CENTER={center}, straight={straight}; specimens={run}')
sys.exit(0 if ok else 1)
PY
