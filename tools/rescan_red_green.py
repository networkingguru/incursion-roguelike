#!/usr/bin/env python3
"""Explicit inc-pd5xn mutation rehearsal; not a gate check.

Run only with authorization to temporarily revert the rescan fix in src/.
Every specimen goes under logs/. No git state is changed. Each mutation is
restored byte-for-byte before rebuilding and rerunning the green check.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
os.chdir(root)
out = Path(tempfile.mkdtemp(prefix='rescan-proof-', dir=root / 'logs'))
print(out, flush=True)
paths = [Path('src/Monster.cpp'), Path('src/Term.cpp'), Path('src/Target.cpp')]
original = {p: p.read_bytes() for p in paths}
stat = subprocess.check_output(['git', 'diff', '--stat'])
(out / 'start-stat.txt').write_bytes(stat)
for p, data in original.items():
    (out / (p.name + '.original')).write_bytes(data)

mutations = [
    ('AC1-trigger', paths[0], b'    if (fresh)\n      ts.Retarget(this);',
     b'    if (false && fresh)\n      ts.Retarget(this);'),
    ('AC1-draw', paths[1], b'        p->JournalNoteMonster((Monster *)t);',
     b'        p->JournalNoteMonster((Monster *)t);\n        ((Monster *)t)->ts.Retarget((Creature *)t); // temporary pre-fix behavior'),
    ('AC2-range', paths[2], b'GatherInSenseRange(me, me->LongestSenseRange(), true, cand);',
     b'GatherInSenseRange(me, 18, true, cand);'),
    ('AC3-item', paths[2], b'    if (it->isItem() && !me->Perceives(it))\n      continue;',
     b'    /* temporary pre-fix behavior: rate unperceived items too */'),
]


def run(label, command, expected):
    print(f'{label}: starting', flush=True)
    with (out / (label + '.log')).open('w') as log:
        rc = subprocess.run(command, env={**os.environ, 'BACKEND': 'posix'},
                            stdout=log, stderr=subprocess.STDOUT).returncode
    print(f'{label}: exit {rc}', flush=True)
    if rc != expected:
        raise RuntimeError(f'{label}: expected {expected}, got {rc}; see {out}')


try:
    for label, path, old, new in mutations:
        if original[path].count(old) != 1:
            raise RuntimeError(f'{label}: mutation anchor is not unique')
        if any(p.read_bytes() != data for p, data in original.items()):
            raise RuntimeError('source changed since snapshot; refusing mutation')
        path.write_bytes(original[path].replace(old, new, 1))
        try:
            run(label + '-red-build', ['./build_macos.sh'], 0)
            run(label + '-red', ['tools/check_rescan_trigger.sh'], 1)
        finally:
            path.write_bytes(original[path])
        run(label + '-green-build', ['./build_macos.sh'], 0)
        run(label + '-green', ['tools/check_rescan_trigger.sh'], 0)
        if any(p.read_bytes() != data for p, data in original.items()):
            raise RuntimeError('byte-for-byte restoration failed')
        now = subprocess.check_output(['git', 'diff', '--stat'])
        if now != stat:
            raise RuntimeError('git diff --stat changed since start')
        (out / (label + '-restored.txt')).write_text(
            'git diff --stat matches start; source bytes match\n' +
            '\n'.join(f'{p}: {hashlib.sha256(data).hexdigest()}'
                      for p, data in original.items()) + '\n')
except BaseException:
    # An interrupted build must never strand a temporary source edit.
    for p, data in original.items():
        p.write_bytes(data)
    raise
print('All four mutation pairs proved; final build is restored GREEN.', flush=True)
