#!/usr/bin/env python3
"""inc-zm6li: measurement only; normal AI, two dive depths, seeds 1..40.
Counts own-turn streaks (>=10) of a monster whose route search points into a
closed door while it neither moves, opens nor bashes; classes a/b/c/d."""
import json, os, re, pathlib, subprocess, tempfile, time, sys
root = pathlib.Path(__file__).resolve().parent.parent
runs = pathlib.Path(tempfile.mkdtemp(prefix='door-stuck-', dir=root/'logs'))
print('runs='+str(runs), flush=True)
results=[]
for depth in (4,9):
    for seed in range(1,41):
        run=runs/f'depth-{depth}-seed-{seed}'
        env=os.environ.copy()
        for key in ('INCURSION_FORCE_PURSUE','INCURSION_ROUTE_PROBE','INCURSION_LOAD','INCURSION_SEED_OVERRIDE','INCURSION_LAUNCHER'):
            env.pop(key,None)
        env.update(INCURSION_BIN=str((root/(sys.argv[1] if len(sys.argv)>1 else 'incursion-door-stuck-final')).resolve()),INCURSION_RUN_DIR=str(run),
                   INCURSION_OPTIONS=str(root/'tools/gates/Options.Dat'),INCURSION_MAP_AUDIT='0')
        start=time.monotonic()
        with (runs/f'depth-{depth}-seed-{seed}.out').open('w') as out:
            child=subprocess.Popen([str(root/'tools/headless.sh'),f'tools/keys/dive-depth-{depth}.keys',str(seed)],
                                   cwd=root,env=env,stdout=out,stderr=subprocess.STDOUT)
            try:
                rc=child.wait(timeout=240)
                status='finished' if rc==0 else 'ERROR'
            except subprocess.TimeoutExpired:
                child.terminate(); rc=child.wait(); status='TIMEOUT'
        row=dict(depth=depth,seed=seed,exit=rc,status=status,wall_s=time.monotonic()-start,run=str(run))
        results.append(row); print(json.dumps(row),flush=True)
        (runs/'results.json').write_text(json.dumps(results,indent=2)+'\n')
print('run_directories='+str(sum(p.is_dir() for p in runs.iterdir())),flush=True)

# Summary: DOORSTUCK lines from every run's stderr (.out file).
pairs=[]
for out in sorted(runs.glob('depth-*-seed-*.out')):
    for line in out.read_text(errors='replace').splitlines():
        if line.startswith('DOORSTUCK mon='):
            kv=dict(re.findall(r'(\w+)=(\S+)',line)); kv['run']=out.stem
            kv['actions']=kv.get('actions',''); pairs.append(kv)
print('total='+str(len(pairs)))
for c in 'abcd':
    print('class_'+c+'='+str(sum(1 for q in pairs if q['class']==c)))
for q in sorted(pairs,key=lambda q:-int(q['own_turns']))[:5]:
    print('worst run=%s mon=%s door=%s at=%s own_turns=%s class=%s ticks=%s..%s actions=%s'%(
        q['run'],q['mon'],q['door'],q['at'],q['own_turns'],q['class'],q['first_tick'],q['end_tick'],q['actions']))
