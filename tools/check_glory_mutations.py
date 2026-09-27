#!/usr/bin/env python3
# gate: none -- it edits tracked source, rebuilds and restores to prove
# tools/check_glory.sh can fail; run it by hand, never in the gate.
"""inc-g1q1: reproduce the three brief-2 mutations, restoring source and build."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
paths = [Path(p) for p in ('src/Magic.cpp', 'lib/pspells.irh', 'lib/wspells.irh')]
originals = {p: p.read_text() for p in paths}
env = dict(os.environ, BACKEND='posix')

def run(command, name):
    log = Path('logs') / ('glory3-' + name + '.log')
    with log.open('w') as out:
        result = subprocess.run(command, env=env, stdout=out, stderr=subprocess.STDOUT)
    return result.returncode, log.read_text()

def restore():
    for path, text in originals.items():
        path.write_text(text)

try:
    rc, _ = run(['./build_macos.sh'], 'baseline-build')
    if rc:
        raise RuntimeError('baseline build failed')
    rc, _ = run(['tools/check_glory.sh'], 'baseline-green')
    if rc:
        raise RuntimeError('baseline probe failed')
    for mutation in ('dc', 'val', 'scale'):
        restore()
        if mutation == 'dc':
            p = paths[0]
            p.write_text(originals[p].replace('rID dcID = RedirectDCSource(e);', 'rID dcID = 0;'))
        else:
            for p in paths[1:]:
                s = originals[p]
                if mutation == 'val':
                    for flag in ('EFF_FLAG1', 'EFF_FLAG2'):
                        s = s.replace('GetEffStatiVal(' + flag, 'GetEffStatiMag(' + flag)
                else:
                    s = s.replace('* 0x10000;', '* 0xFFFF;')
                p.write_text(s)
        rc, _ = run(['./build_macos.sh'], 'mutation-' + mutation + '-build')
        if rc:
            raise RuntimeError(mutation + ' build failed')
        rc, output = run(['tools/check_glory.sh'], 'mutation-' + mutation)
        category = 'dc child=' if mutation == 'dc' else ('mm-scale child=' if mutation == 'scale' else 'mm child=')
        failures = [line for line in output.splitlines() if category in line and 'FAIL' in line]
        expected = 4 if mutation == 'dc' else 2
        if mutation == 'scale' and any('high=0' not in line for line in failures):
            raise RuntimeError('scale mutation did not lose the high-half flag')
        if rc != 1 or len(failures) != expected:
            raise RuntimeError(mutation + ' did not fail the expected cases')
        print(mutation + ': expected RED', flush=True)
        print('\n'.join(failures), flush=True)
finally:
    restore()
    rc, _ = run(['./build_macos.sh'], 'restored-build')
    if rc:
        raise RuntimeError('restored build failed')
rc, output = run(['tools/check_glory.sh'], 'restored-green')
print(output, end='')
if rc:
    raise SystemExit(rc)
