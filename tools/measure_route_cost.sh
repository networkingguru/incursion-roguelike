#!/bin/bash
# Measure (not a pass/fail gameplay check) inc-vhkei route cost.
# Usage: tools/measure_route_cost.sh BINARY [--timeout SECONDS] [SEED ...]
# Default seeds: 1..40, matching gate_record.sh; timeout: 120 wall seconds.
# Each invocation owns logs/route-cost-*/seed-N via INCURSION_RUN_DIR.
# Map audit is disabled for timing, per headless.sh. Nonzero exits are ERROR,
# never silently called finished. TIMEOUT counters are the last completed-call
# snapshot; snapshot_age_s exposes its staleness. stderr retains all snapshots.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 - "$ROOT" "$@" <<'PY'
import argparse, json, os, pathlib, re, signal, subprocess, sys, tempfile, time
root = pathlib.Path(sys.argv[1])
p = argparse.ArgumentParser(description='Measure dive route cost with a per-seed wall timeout')
p.add_argument('binary', type=pathlib.Path)
p.add_argument('--timeout', type=float, default=120)
p.add_argument('seeds', type=int, nargs='*')
a = p.parse_intermixed_args(sys.argv[2:])
if a.timeout <= 0 or any(s < 1 for s in a.seeds) or len(set(a.seeds)) != len(a.seeds):
    p.error('timeout and seeds must be positive; seeds must be unique')
binary = a.binary.resolve()
if not binary.is_file() or not os.access(binary, os.X_OK):
    p.error('binary is not executable')
runroot = pathlib.Path(tempfile.mkdtemp(prefix='route-cost-', dir=root/'logs'))
print('runs=' + str(runroot), flush=True)
results = []
for seed in a.seeds or range(1, 41):
    run = runroot / ('seed-%d' % seed)
    env = os.environ.copy()
    for key in ('INCURSION_LOAD', 'INCURSION_LAUNCHER', 'INCURSION_SEED_OVERRIDE'):
        env.pop(key, None)
    env.update(INCURSION_BIN=str(binary), INCURSION_RUN_DIR=str(run),
               INCURSION_OPTIONS=str(root/'tools/gates/Options.Dat'),
               INCURSION_MAP_AUDIT='0', INCURSION_SAVE_PROBE='1')
    with (runroot/('seed-%d.out' % seed)).open('w') as log:
        start = time.monotonic()
        child = subprocess.Popen([str(root/'tools/headless.sh'),
            'tools/keys/dive.keys', str(seed)], cwd=root, env=env,
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        outcome = 'finished'
        try:
            rc = child.wait(timeout=a.timeout)
        except subprocess.TimeoutExpired:
            outcome = 'TIMEOUT'
            os.killpg(child.pid, signal.SIGTERM)
            try:
                rc = child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                rc = child.wait()
        wall = time.monotonic()-start
    text = (runroot/('seed-%d.out' % seed)).read_text(errors='replace')
    snapshots = re.findall(r'^PATHPROBE (.*)$', text, re.M)
    counters = dict(re.findall(r'(\w+)=([\d.]+)', snapshots[-1])) if snapshots else {}
    if outcome != 'TIMEOUT' and rc != 0:
        outcome = 'ERROR'
    row = dict(seed=seed, wall_s=wall, outcome=outcome, exit=rc, counters=counters)
    if counters:
        row['snapshot_age_s'] = max(0, time.clock_gettime(time.CLOCK_MONOTONIC)-float(counters['stamp']))
        for result in ('hit', 'unreach'):
            n = int(counters[result])
            row[result+'_pops_per_call'] = int(counters[result+'_pops'])/n if n else 0
    else:
        row['probe'] = 'MISSING'
    results.append(row)
    print(json.dumps(row), flush=True)
    (runroot/'results.json').write_text(json.dumps(results, indent=2)+'\n')
print(json.dumps(dict(total_wall_s=sum(r['wall_s'] for r in results),
    timeouts=sum(r['outcome']=='TIMEOUT' for r in results),
    errors=sum(r['outcome']=='ERROR' for r in results),
    slowest=sorted(results, key=lambda r:r['wall_s'], reverse=True)[:5])), flush=True)
sys.exit(2 if any(r['outcome']=='ERROR' or not r['counters'] for r in results) else 0)
PY
