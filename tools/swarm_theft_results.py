#!/usr/bin/env python3
"""inc-67gh probe consumer. Random dice and item identities are never gate oracles.

The future opposed resolver must emit its ACTUAL operands on the attempt line:
thief_hit, thief_dex, thief_bonus, thief_roll, thief_total;
victim_bab, victim_str, victim_dex, victim_half_level, victim_pick,
victim_theft, victim_bonus, victim_roll, victim_total.
Do not populate those fields with a parallel prediction of the desired formula.
The current save resolver intentionally emits kind=save and fails case c.
"""
import collections
import pathlib
import re
import statistics
import sys

base = pathlib.Path(sys.argv[1])
measure = '--measure' in sys.argv

def records(name):
    text = (base / (name + '.out')).read_text()
    rows = []
    for line in text.splitlines():
        if not line.startswith('SWARM_THEFT '):
            continue
        row = dict(re.findall(r'(\w+)=(-?\d+|save|opposed)(?=\s|$)', line))
        row['event'] = line.split()[1]
        rows.append(row)
    return text, rows

def survived(name):
    if (base / (name + '.exit')).read_text().strip() != '0':
        return False
    screens = sorted((base / name / 'logs/screens').glob('*.txt'))
    hp = re.findall(r'HP:(\d+)/', screens[-1].read_text()) if screens else []
    death = base / name / 'logs/death.log'
    return bool(hp and int(hp[-1]) > 0 and not (death.exists() and death.stat().st_size))

def sheet(name):
    text = pathlib.Path(f'tools/fixtures/chars/{name}.sheet.txt').read_text()
    level = int(re.search(r'^Class\s+\w+ (\d+)', text, re.M)[1])
    bab = int(re.search(r'Melee\s+\+toHit.*?\(\w+ ([+-]\d+)', text)[1])
    attrs = [int(re.search(rf'^{a}:.*?\[([+-]\d+)/', text, re.M)[1]) for a in ('STR', 'DEX')]
    pick = max(0, int(re.search(r'^  Pick Pockets\s+([+-]\d+)', text, re.M)[1]) // 3)
    # Neither fixture has a SAVE_BONUS SN_THEFT item/spell; the sheet's
    # '+2 vs. theft' for the Rogue is the Pick Pockets contribution itself.
    return dict(victim_bab=bab, victim_str=attrs[0], victim_dex=attrs[1],
                victim_half_level=level // 2, victim_pick=pick, victim_theft=0)

if measure:
    dirs = sorted(p for p in base.glob('seed-*') if p.is_dir())
    print(f'Specimens: {base}; run directories={len(dirs)}')
    losses = []
    valid = len(dirs) == 20
    for seed in range(1, 21):
        name = f'seed-{seed}'
        text, rows = records(name)
        transfers = [r for r in rows if r['event'] == 'transfer' and r['player'] == '1']
        screens = sorted((base / name / 'logs/screens').glob('*.txt'))
        marks = {re.search(r'screen \d+ (\S+)', p.read_text())[1]:
                 int(re.search(r' turn (\d+)', p.read_text())[1]) for p in screens}
        ticks = marks.get('swarm-end', 0) - marks.get('swarm-created', 0)
        exercised = any(r['event'] == 'adjacency' and int(r['enemies']) > 0 for r in rows)
        ok = survived(name) and ticks == 240 and exercised
        count = sum(int(r['quantity']) for r in transfers)
        losses.append(count)
        valid &= ok
        print(f'seed={seed} items_lost={count} transfers={len(transfers)} ticks={ticks} valid={int(ok)}')
    print(f'mean items lost={statistics.mean(losses):.3f}' if valid else 'INCONCLUSIVE: invalid measurement run')
    sys.exit(0 if valid else 2)

results = []
def result(case, status, detail):
    results.append(status)
    print(f'{case}: {status} — {detail}')

runs = {}
for name in ('warrior', 'crowd', 'defense', 'mundane', 'recovery'):
    text, rows = records(name)
    runs[name] = rows if survived(name) else []

adj = [r for r in runs['warrior'] if r['event'] == 'adjacency']
result('a', 'PASS' if adj and all(r['cr'] == '4' for r in adj) else 'FAIL' if adj else 'INCONCLUSIVE',
       'live CR=' + ','.join(sorted({r['cr'] for r in adj})))
adj = [r for r in runs['crowd'] if r['event'] == 'adjacency' and int(r['enemies']) >= 2]
counts = collections.Counter((r['turn'], r['thief']) for r in runs['crowd'] if r['event'] == 'attempt' and r['swarm'] == '1')
maximum = max((counts[r['turn'], r['thief']] for r in adj), default=0)
result('b', 'FAIL' if maximum > 1 else 'PASS' if adj and maximum else 'INCONCLUSIVE',
       f'eligible turns={len(adj)}, maximum attempts={maximum}')
for name, fixture in [('warrior', 'alignment-drain-warrior'), ('defense', 'skill-by-name-seed1-opt0818')]:
    attempts = [r for r in runs[name] if r['event'] == 'attempt' and r['swarm'] == '1' and r['player'] == '1']
    expected = sheet(fixture)
    expected['victim_bonus'] = (expected['victim_bab'] + max(expected['victim_str'], expected['victim_dex'])
                                + expected['victim_half_level'] + expected['victim_pick'] + expected['victim_theft'])
    expected.update(thief_hit=3, thief_dex=3, thief_bonus=6)
    good = attempts and all(r['kind'] == 'opposed'
                            and all(k in r for k in ('thief_roll', 'thief_total', 'victim_roll', 'victim_total'))
                            and all(r.get(k) == str(v) for k, v in expected.items()) for r in attempts)
    result('c/' + name, 'PASS' if good else 'FAIL' if attempts else 'INCONCLUSIVE',
           f'kinds={sorted({r["kind"] for r in attempts})}; expected components={expected}')
attempts = [r for r in runs['mundane'] if r['event'] == 'attempt' and r['swarm'] == '0' and r['player'] == '1']
result('d', 'PASS' if attempts and all(r['kind'] == 'save' for r in attempts) else 'FAIL' if attempts else 'INCONCLUSIVE',
       f'ordinary thief attempts={len(attempts)}')
stolen = {(r['thief'], r['item']) for r in runs['recovery'] if r['event'] == 'transfer' and r['player'] == '1'}
recovered = [r for r in runs['recovery'] if r['event'] == 'recovery' and r['swarm'] == '1' and
             r['summoned'] == '0' and r['dead'] == '0' and (r['victim'], r['item']) in stolen]
result('e', 'PASS' if recovered else 'INCONCLUSIVE', f'exact stolen handles recovered alive={len(recovered)}')
print(f'Specimens: {base}')
# Missing controls must never masquerade as a red design assertion.
sys.exit(2 if 'INCONCLUSIVE' in results else 1 if 'FAIL' in results else 0)
