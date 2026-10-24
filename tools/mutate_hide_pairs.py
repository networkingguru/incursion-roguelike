#!/usr/bin/env python3
# inc-yp23: reproduce each brief-requested mutation, restore exact text, rebuild.
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
os.chdir(root)
source = pathlib.Path('src/HideCheck.cpp')
original = source.read_bytes()
text = original.decode()
assert 'yt.movedAt > prevScan' in text, 'requires the fixed implementation'
out = pathlib.Path('logs/hide-pairs-mutations')
out.mkdir(parents=True, exist_ok=True)
(out / 'fixed-original.cpp').write_bytes(original)

def replace(old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)

start = text.index('    if (x->m) {', text.index('void HideTurnStart'))
end = text.index('    if (!isValidHandle(xHandle)) return;', start)
mutations = {
    'M1': replace('        if (!yk->HasStati(HIDING)) continue;', '''        if (xk->HasStati(HIDING)) {
            if (getenv("INCURSION_HIDE_PAIRS_PROBE"))
                Error("HIDE_PAIRS CALL watcher=%d hider=%d",
                    (int)yk->myHandle, (int)xk->myHandle);
            HideUpdatePair(yk, xk);
        }
        if (!yk->HasStati(HIDING)) continue;'''),
    'M2': replace('const bool full = xt.fullRound != round ||', 'const bool full = true || xt.fullRound != round ||'),
    'M3': replace('full || yt.movedAt > prevScan', 'full'),
    'M4': replace('xt.fullRound != round ||\n                      ', ''),
    'M5': text[:start] + text[end:],
    'M6': replace('yt.movedAt > prevScan', 'yt.movedAt > xt.scanAt'),
}
expected = {'M1':['1_turn'], 'M2':['2'], 'M3':['3a','3b'], 'M4':['4'], 'M5':['5'], 'M6':['3b','3e']}

def run(command, name):
    with (out / name).open('w') as log:
        rc = subprocess.call(command, stdout=log, stderr=subprocess.STDOUT,
                             env=dict(os.environ, BACKEND='posix'))
    print(f'{name}: exit {rc}', flush=True)
    return rc

for name in sys.argv[1:] or mutations:
    assert name in mutations, name
    try:
        source.write_text(mutations[name])
        assert run(['./build_macos.sh'], name+'-build.log') == 0
        rc = run(['tools/check_hide_pairs.sh'], name+'.txt')
        result = (out / (name+'.txt')).read_text()
        print('\n'.join(s for s in result.splitlines() if s.startswith('RED:')), flush=True)
        assert rc == 1 and all(f'RED: rule {case}:' in result for case in expected[name]), name
    finally:
        source.write_bytes(original)
        assert source.read_bytes() == original
        assert run(['./build_macos.sh'], name+'-restore-build.log') == 0
    assert run(['tools/check_hide_pairs.sh'], name+'-restored.txt') == 0
