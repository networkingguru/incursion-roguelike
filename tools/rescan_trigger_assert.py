#!/usr/bin/env python3
"""Gameplay oracle for check_rescan_trigger.sh (inc-pd5xn)."""
import pathlib
import re
import sys

base = pathlib.Path(sys.argv[1])


def plain(path):
    return ''.join(c for c in path.read_bytes().decode('latin1')
                   if c in '\n\t' or 32 <= ord(c) < 127)


def scene(name, xy):
    run = base / name
    stage = plain(run / 'logs/runtoprobe.log')
    if 'stage mode=R origin=5,5 len=30 pocket=20,7 player=5,5' not in stage:
        raise ValueError(f'{name}: corridor staging not established')
    lines = plain(run / 'logs/rescan-probe.log').splitlines()
    ts = []
    rs = []
    for index, line in enumerate(lines):
        t = re.fullmatch(r'T (\d+) M (.*?) h=(\d+) at=(\d+),(\d+) range=(\d+) seen=([01]) fresh=([01]) new=(.*)', line)
        r = re.fullmatch(r'R (\d+) M (.*?) h=(\d+) force=(\d+) n=(\d+) targets=(.*)', line)
        if t:
            turn, name_, handle, x, y, sense, seen, fresh, new = t.groups()
            ts.append(dict(index=index, turn=int(turn), handle=handle,
                           xy=(int(x), int(y)), sense=int(sense),
                           seen=int(seen), fresh=int(fresh), new=new))
        elif r:
            turn, name_, handle, force, count, targets = r.groups()
            rs.append(dict(index=index, turn=int(turn), handle=handle, targets=targets))
    if len(ts) < 3 or any(t['xy'] != xy or t['sense'] != 24 for t in ts):
        raise ValueError(f'{name}: held vrock at {xy} with range 24 not established')
    if len({t['handle'] for t in ts}) != 1:
        raise ValueError(f'{name}: unexpected additional watcher')
    return ts, rs


def following(t, ts, rs):
    end = next((n['index'] for n in ts if n['index'] > t['index']), float('inf'))
    return [r for r in rs if t['index'] < r['index'] < end
            and r['handle'] == t['handle'] and r['turn'] == t['turn']]


failures = []


def check(ac, ok, message):
    print(f'{ac}: {"PASS" if ok else "FAIL"}: {message}')
    if not ok:
        failures.append(ac)


try:
    hidden, hr = scene('trigger', (35, 5))
    visible, vr = scene('trigger-visible', (35, 5))
    items, ir = scene('items', (20, 5))
    fresh = [t for t in hidden if t['fresh'] and t['seen'] == 0 and '@11,5' in t['new']]
    check('AC1', bool(fresh) and all(following(t, hidden, hr) for t in fresh),
          'unseen watcher rescans immediately when player enters its senses')
    stale = [t for t in hidden[1:] if t['seen'] and not t['fresh']]
    check('AC1', len(stale) >= 2 and not any(following(t, hidden, hr) for t in stale),
          'drawing a visible watcher without new perception does not rescan')
    check('AC1', any(t['seen'] for t in visible) and
          [(t['turn'], t['fresh'], t['new']) for t in hidden] ==
          [(t['turn'], t['fresh'], t['new']) for t in visible] and
          [(r['turn'], r['targets']) for r in hr] == [(r['turn'], r['targets']) for r in vr],
          'player visibility leaves perception and rescan moments unchanged')
    check('AC2', bool(fresh) and any('@11,5' in r['targets']
          for t in fresh for r in following(t, hidden, hr)),
          'rescan includes the perceived creature 24 squares away (beyond 18)')
    shot = next((base / 'items/logs/screens').glob('*rescan-hidden-rated*'))
    boundary = int(re.search(r' turn (\d+) ===', plain(shot)).group(1))
    before = [r for r in ir if r['turn'] < boundary]
    after = [r for r in ir if r['turn'] >= boundary]
    check('AC3', bool(before) and all('dagger@20,7' not in r['targets'] for r in before)
          and all('dagger@20,7' not in t['new'] for t in items if t['turn'] < boundary),
          'opaque pocket item is neither perceived nor rated inside sense range')
    check('AC3', any('dagger@20,7' in t['new'] and t['fresh'] for t in items
                    if t['turn'] >= boundary) and
          any('9:dagger@20,7' in r['targets'] for r in after),
          'opening the wall makes the same item newly perceived and rated')
except (OSError, ValueError, StopIteration, AttributeError) as error:
    print(f'INCONCLUSIVE: {error}; runs={base}')
    sys.exit(2)
sys.exit(1 if failures else 0)
