#!/usr/bin/env bash
# inc-rabe observation only: AI choices are uncontrolled, so this is not a check.
# Same RouteProbe scene as check_monster_route_to_target.sh; 24 one-turn rests
# exceed the U corridor's 12 orthogonal steps by 12. Overview samples cost no turn.
# Usage: tools/observe_monster_route.sh [seed]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
mkdir -p logs/runs
run=$(mktemp -d "$PWD/logs/runs/monster-route-observe.XXXXXX") || exit 2
INCURSION_ROUTE_PROBE=1 INCURSION_RUN_DIR="$run" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/kobold-rogue-seed1.sav \
    tools/headless.sh tools/keys/monster-route-observe.keys "${1:-3}" > "$run/harness.txt" 2>&1
rc=$?
python3 - "$run" "$rc" <<'PY'
import pathlib, sys
run = pathlib.Path(sys.argv[1])
log = run / 'logs/routeprobe.log'
print(f'specimens={run}; headless exit={sys.argv[2]}')
if not log.exists():
    print('No observation available'); sys.exit(0)
lines = log.read_text().splitlines()
print('\n'.join(lines))
obs = [dict(x.split('=', 1) for x in line.split()[1:]) for line in lines if line.startswith('observe ')]
first = next((x for x in obs if x['adjacent'] == '1'), None)
print('first adjacent: ' + (f"rest {first['rest']} (tick {first['tick']})" if first else 'never'))
print(f'observed {max(0, len(obs)-1)} of 24 requested rests')
PY
