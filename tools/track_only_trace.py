#!/usr/bin/env python3
"""Evaluate event-time violations and tracking-only pursuit/exercise separately."""
import pathlib, re, sys
run = pathlib.Path(sys.argv[1])
rows = []
spell = "none"
armed = sys.argv[2] == "armed"
for f in sorted((run / 'logs/screens').glob('*-track*.txt')):
    s = ' '.join(line.split('|', 1)[0] for line in f.read_text().splitlines()[1:])
    s = ' '.join(s.split())
    samples = re.findall(r'Track (\d+): d (\d+) per (\d+) lof (\d+) mana (-?\d+)', s)
    attempts = re.findall(r'Attempts (\d+) forbidden (\d+) first (\d+) d (\d+) per (\d+) event (\d+)', s)
    if samples and attempts:
        rows.append(tuple(map(int, samples[-1] + attempts[-1])))
        spells = re.findall(r'Attempted spell: (.*?) Track read', s)
        if spells:
            spell = spells[-1].strip()
header = 'sample distance perceives lof mana attempts forbidden first_sample first_distance first_perceives event\n'
(run / 'trace.txt').write_text(header + ''.join(' '.join(map(str, r)) + '\n' for r in rows))
print('specimens:', run)
eligible = [r for r in rows if armed and r[2] == 512 and r[3] == 1 and r[4] >= 8]
approach = any(a[1] > b[1] for a, b in zip(rows, rows[1:]) if a[2] == b[2] == 512)
print(f'samples={len(rows)} eligible={len(eligible)} tracking-only approach={approach}')
tracking = [r for r in rows if r[2] == 512]
if tracking:
    print(f'tracking-only distance: {tracking[0][1]} -> {tracking[-1][1]}; '
          f'attempts={sum(r[5] for r in rows)} forbidden={rows[-1][6]}')
bad = next((r for r in rows if r[6]), None)
if bad:
    print(f'FAIL: sample {bad[7]} distance {bad[8]} Perceives={bad[9]} (0x{bad[9]:x}) attempted event={bad[10]} (PRE_INVOKE=536, PRE_CAST=537) spell={spell}')
    sys.exit(1)
if [r[0] for r in rows] != list(range(80)) or len(eligible) < 20 or not approach:
    print('INCONCLUSIVE: no forbidden attempt; insufficient armed tracking-only exercise or approach')
    sys.exit(2)
print('PASS: no tracking-only attack attempts; >=20 eligible samples and measured approach')
