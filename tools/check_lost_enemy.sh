#!/bin/bash
# gate: live
# inc-9622: expected-after-fix arrival oracle, deliberately RED on unfixed AI.
# Usage: tools/check_lost_enemy.sh [seed]
# Build separately: BACKEND=posix ./build_macos.sh
# 0 all GREEN; 1 acceptance failure (RED); 2 invalid/incomplete experiment.
# The two manual controls use the SAME distance/perception assertion as A/B.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo 'INCONCLUSIVE: build the posix backend'; exit 2; }
mkdir -p logs
BASE="$(mktemp -d "$PWD/logs/lost-enemy-XXXXXX")"
for mode in lost noise lost-control noise-control; do
    INCURSION_LOST_ENEMY_PROBE="$mode" INCURSION_RUN_DIR="$BASE/$mode" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav \
        tools/headless.sh tools/keys/lost-enemy-test.keys "${1:-1}" > "$BASE/$mode.out" 2>&1
    echo "$?" > "$BASE/$mode.status"
done
python3 - "$BASE" <<'PY'
import pathlib, sys
base = pathlib.Path(sys.argv[1])
failed = invalid = False
for mode in ('lost', 'noise', 'lost-control', 'noise-control'):
    log = base / mode / 'logs/lost-enemy.log'
    lines = log.read_text().splitlines() if log.exists() else []
    rows = [dict(part.split('=', 1) for part in s.split()[1:])
            for s in lines if s.startswith('TURN ')]
    if (int((base / f'{mode}.status').read_text()) not in (0, 3)
            or 'COMPLETE' not in lines or any('INCONCLUSIVE' in s for s in lines)
            or [int(r['turn']) for r in rows] != list(range(41))):
        print(f'{mode}: INCONCLUSIVE; {log}')
        invalid = True
        continue
    start = int(rows[0]['distance'])
    closest = min(int(r['distance']) for r in rows[1:])
    # Turn zero still has the previous visible turn's cached target.vis.
    # Every action thereafter must observe zero perception of the relocated player.
    unseen = all(int(r['perceived']) == 0 for r in rows)
    if not mode.endswith('control'):
        unseen &= all(int(r['vis']) == 0 for r in rows[1:])
    active = all(int(r['asleep']) == int(r['afraid']) == 0 for r in rows)
    passed = start > 1 and closest <= 1 and unseen and active
    fields = (f'start={start} closest={closest} turns={len(rows)-1} '
              f'unseen={int(unseen)} awake_nonfleeing={int(active)}')
    # inc-9622 phase 2c: live observation of the investigate window. No control
    # carries this assertion: the control teleports the monster without ever
    # giving it an investigate target, so it holds no TargetArea to search or
    # drop.
    if not mode.endswith('control'):
        # The arrival window is the passes on which searchTurns is non-zero.
        # Before arrival searchTurns==0: those passes may still carry the
        # one-in-three lost-sight/heard-noise search, which is a different,
        # pre-existing mechanism and is not the 5-turn investigate window.
        held = [r for r in rows if int(r['held']) == 1]
        arrived = [r for r in held if int(r['searchTurns']) != 0]
        searches = sum(1 for r in arrived if int(r['action']) == 32)
        last_arrived = arrived[-1]['turn'] if arrived else None
        gone_after = any(int(r['held']) == 0 and (last_arrived is None or
                          int(r['turn']) > int(last_arrived)) for r in rows)
        dropped = 1 if arrived and gone_after else 0
        # Each arrived pass must actually search (the window runs searchTurns
        # 1..5 and the pass after the fifth forgets the target, not searched),
        # so the search count equals the arrived-pass count.
        ok = searches == 5 and len(arrived) == 5 and dropped == 1
        passed &= ok
        fields += f' searches={searches} dropped={dropped}'
    print(f'{mode}: {"GREEN" if passed else "RED"} {fields}')
    failed |= not passed
print(f'Specimens: {base}')
sys.exit(2 if invalid else 1 if failed else 0)
PY
