#!/bin/bash
# gate: live
# inc-yp23: watcher-side pair re-tests; 0 GREEN, 1 RED, 2 INCONCLUSIVE.
# fact: character and starting map -- INCURSION_LOAD fixture orc-rogue-seed1-opt0822.sav
# fact: options -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: creatures, squares, hiding and sight state -- INCURSION_HIDE_PAIRS_PROBE scene setup (brief-authorized probe control)
# fact: same/next round -- probe holds Turn fixed or advances HIDE_ROUND_TICKS
# fact: pair re-test calls -- env-gated log at the real HidePairsFor call site; no dice outcome read
# fact: result-note presence -- real baseline scan creates notes for either roll outcome; probe checks presence only
# fact: case names and creature identities -- literal probe labels and handles read from SCENE, no generated text
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo 'INCONCLUSIVE: build posix backend'; exit 2; }
mkdir -p logs
RUN="$(mktemp -d "$PWD/logs/hide-pairs-XXXXXX")"
INCURSION_HIDE_PAIRS_PROBE=1 INCURSION_RUN_DIR="$RUN" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav \
 tools/headless.sh tools/keys/hide-pairs.keys "${1:-1}" > "$RUN.out" 2>&1
status=$?
python3 - "$RUN" "$status" <<'PY'
import pathlib, re, sys
run = pathlib.Path(sys.argv[1])
log = run / 'logs/errors.log'
lines = [s for s in log.read_text().splitlines() if not s.startswith('    ') and 'HIDE_PAIRS' in s] if log.exists() else []
pathlib.Path(str(run)+'.lines').write_text('\n'.join(lines)+'\n')
if int(sys.argv[2]) not in (0,3) or any('INCONCLUSIVE' in s for s in lines) or not any('HIDE_PAIRS COMPLETE' in s for s in lines):
    print(f'INCONCLUSIVE: incomplete probe or headless exit {sys.argv[2]}; {run}.lines'); sys.exit(2)
scene = [re.search(r'SCENE h=(\d+) w=(\d+) w2=(\d+)', s) for s in lines]
scene = [m for m in scene if m]
if len(scene) != 1:
    print(f'INCONCLUSIVE: missing/duplicate scene; {run}.lines'); sys.exit(2)
h,w,w2 = map(int,scene[0].groups())
expected = {'1_turn':0,'1_pairs':0,'1_watcher':1,'2':0,'3a':1,'3b':1,'3c':1,'3d_range':1,'3d_blind':1,'3d_asleep':1,'3e':1,'4':1,'5':0}
cases={}; ends={}; current=None; bad=[]
for s in lines:
    if ' BEGIN case=' in s:
        name=s.split('case=')[1]
        if current is not None or name in cases: bad.append('duplicate/nested case '+name)
        current=name; cases[name]=[]
    elif ' CALL ' in s and current is not None:
        m=re.search(r'watcher=(\d+) hider=(\d+)$',s)
        if not m: bad.append('malformed call '+s)
        else: cases[current].append(tuple(map(int,m.groups())))
    elif ' END ' in s:
        if current is None: bad.append('unpaired END'); continue
        ends[current]=s; current=None
if current is not None or set(cases)!=set(expected): bad.append('case set differs')
for name,want in expected.items():
    rows=cases.get(name,[])
    got=sum(b==h for a,b in rows) if name in ('1_turn','1_pairs') else rows.count((w,h))
    ok=got==want
    if name=='5': ok=ok and 'before_far=1 before_near=1 after_far=0 after_near=1' in ends.get(name,'')
    print(f'{"GREEN" if ok else "RED"}: rule {name}: pair calls expected={want} got={got}'+(' '+ends.get(name,'') if name=='5' else ''))
    if not ok: bad.append(name)
print(f'{"RED" if bad else "GREEN"}: hide pairs; failures={bad}; Run: {run}')
sys.exit(1 if bad else 0)
PY
