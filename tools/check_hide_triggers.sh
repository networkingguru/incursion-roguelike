#!/bin/bash
# gate: live
# inc-u3dp: real player command events; 0 GREEN, 1 RED, 2 INCONCLUSIVE.
# The probe sets the scene and dispatches events, never HideTrigger/SpotCheck.
# Literal expectations below are independent of ItemSizePenalty/HiderModifiers.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo 'INCONCLUSIVE: build the posix backend'; exit 2; }
RUN="$(mktemp -d "$PWD/logs/hide-triggers-XXXXXX")"
INCURSION_HIDE_TRIGGER_PROBE=1 INCURSION_RUN_DIR="$RUN" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav \
    tools/headless.sh tools/keys/hide-triggers.keys "${1:-1}" > "$RUN.out" 2>&1
status=$?
python3 - "$RUN" "$status" <<'PY'
import collections
import pathlib
import re
import sys
run = pathlib.Path(sys.argv[1])
log = run / 'logs/errors.log'
if not log.exists():
    print(f'INCONCLUSIVE: no probe log; {run}.out'); sys.exit(2)
lines = [s for s in log.read_text().splitlines() if not s.startswith('    ') and 'HIDE_TRIGGER' in s]
pathlib.Path(str(run)+'.lines').write_text('\n'.join(lines)+'\n')
if any('INCONCLUSIVE' in s for s in lines) or not any('HIDE_TRIGGER COMPLETE' in s for s in lines):
    print(f'INCONCLUSIVE: incomplete scene/probe; {run}.lines'); sys.exit(2)
if int(sys.argv[2]) not in (0,3):
    print(f'INCONCLUSIVE: headless exit {sys.argv[2]}; {run}.out'); sys.exit(2)
scene = [re.search(r'SCENE player=(\d+) watcher1=(\d+) watcher2=(\d+)',s) for s in lines]
scene = [m for m in scene if m]
if len(scene) != 1:
    print(f'INCONCLUSIVE: expected one scene; {run}.lines'); sys.exit(2)
player,w1,w2 = map(int,scene[0].groups())
penalties = dict(open=-10,close=-10,pickup_tiny=0,pickup_medium=-5,
                 drop=-5,drink=0,read=0,zap=0,activate=0,snipe=-20)
expected = {f'{name}_{h}': (pen,0,h) for name,pen in penalties.items() for h in (0,1)}
expected.update(sprint=(-10,-20,1),song=(0,0,0),hide_singing=(0,0,0),hide_silent=(0,0,1))
# inc-u3dp phase 6: two hard-coded cases whose probe supplies the verdict with
# a forced hiderPenalty, so they carry no expected roll rows.
EXTRA = {'appraise','spot_keeps_hide'}
EXPECTED_CASES = 26
cases = {}; current = None; bad = []; ends = {}
for s in lines:
    if ' BEGIN case=' in s:
        name = s.split('case=')[1]
        if current is not None or name in cases: bad.append('duplicate/nested case '+name)
        current = name; cases[name] = []
    elif 'HIDE_TRIGGER_ROLL' in s and current is not None:
        m = re.search(r'watcher=(\d+) hider=(\d+) hiderPenalty=(-?\d+) HiderModifiers=(-?\d+) result=([01])$',s)
        if not m: bad.append('malformed roll '+s)
        else: cases[current].append(tuple(map(int,m.groups())))
    elif ' END ' in s:
        if current is None: bad.append('unpaired END'); continue
        ends[current] = s
        if not re.search(r' ok=1(?: |$)',s): bad.append(current+': action/state failed: '+s)
        if current.startswith('snipe_1') and not s.endswith('hiding=1'): bad.append('snipe did not keep hide')
        current = None
if len(cases) != EXPECTED_CASES or set(cases) != (set(expected) | EXTRA) or current:
    bad.append(f'case set/count differs: {len(cases)} expected {EXPECTED_CASES}')
# inc-u3dp phase 6: hard-coded word and state checks for the two new cases.
if not re.search(r' ok=1 aware=1 unaware=1(?: |$)', ends.get('appraise','')):
    bad.append('appraise: expected aware=1 unaware=1 in '+ends.get('appraise','<missing>'))
if not re.search(r' ok=1 hiding=1(?: |$)', ends.get('spot_keeps_hide','')):
    bad.append('spot_keeps_hide: expected hiding=1 in '+ends.get('spot_keeps_hide','<missing>'))
for name,rows in cases.items():
    if name not in expected: continue
    pen,mods,hiding = expected[name]
    want = collections.Counter([(w1,player,pen,mods),(w2,player,pen,mods)]) if hiding else collections.Counter()
    got = collections.Counter(r[:4] for r in rows)
    if got != want: bad.append(f'{name}: expected {dict(want)}, got {dict(got)}')
    print(f'{name}: {len(rows)} rolls')
if bad:
    print('RED: '+'\n'.join(bad)+f'\nRun: {run}'); sys.exit(1)
print(f'GREEN: all {EXPECTED_CASES} action cases; two rolls per hiding action, zero per non-hiding action. Run: {run}')
PY
