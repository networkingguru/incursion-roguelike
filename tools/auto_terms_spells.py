#!/usr/bin/env python3
"""inc-g1zfl: spell-mode oracle; staging controls are in check_auto_terms.sh."""
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
prompt = 'Confirm attack fleeing victim?'
results = {}
red_evidence = {}

def dump(run, label):
    paths = list((run / 'logs/screens').glob('*-' + label + '.txt'))
    return paths[0].read_text() if len(paths) == 1 else ''

def flatten(raw):
    return re.sub(r'\s+', ' ', ' '.join(
        m.group(1) for line in raw.splitlines()
        if (m := re.match(r'^\s*\|\s?(.*?)\s*\|', line))))

def judge(scene):
    kind = scene.split('-')[0]
    run = out / scene
    fear = run / 'logs/summon-afraid.log'
    cast, after = dump(run, 'spell-cast'), dump(run, 'spell-after')
    screen_log = flatten(dump(run, 'spell-log'))
    trace = run / 'logs/runtoprobe.log'
    log = trace.read_text(errors='replace') if trace.exists() else ''
    switches = dump(run, 'spell-switches')
    summoned = dump(run, 'spell-summoned')
    target = dump(run, 'spell-target')
    turns = [re.search(r' turn (\d+) ===', text) for text in (summoned, target)]
    report = (out / (scene + '.out')).read_text(errors='replace')
    if (not all(turns) or turns[0][1] != turns[1][1]
            or 'ended:      cleanly' not in report):
        print(f'INCONCLUSIVE {scene}: summon/target turn or clean completion not shown')
        sys.exit(2)
    if (not fear.exists() or 'mon=rainbow sprite fear=HP afraid=1 x=43 y=40' not in fear.read_text()
            or not cast or not after or not screen_log or not log
            or "stage mode=R origin=40,40" not in log
            or any(not re.search(name + r'\s+YES', switches)
                   for name in ('Ignore Spell Failure', 'Infinite Mana', 'Freeze Monsters'))):
        print(f'INCONCLUSIVE {scene}: staging/screens missing: {run}')
        sys.exit(2)
    offer = re.search(r'(accepts|refuses) your terms', log)
    spell = 'fireball' if kind == 'S3' else 'magic missile'
    strike = re.search(re.escape(f'Your {spell} ') + r'(strikes|kills) a rainbow sprite\.', log)
    strike_text = strike[0] if strike else ''
    has_prompt = prompt in cast
    any_prompt = prompt in log + cast + after
    if strike and strike_text not in screen_log:
        print(f'INCONCLUSIVE {scene}: strike absent from message screen')
        sys.exit(2)
    if not strike and not offer and not has_prompt:
        print(f'INCONCLUSIVE {scene}: no cast, offer or prompt observed: {log}')
        sys.exit(2)
    if kind in ('S1', 'M1'):
        want = 'accepts' if scene.endswith('-acc') else 'refuses'
        ok = bool(offer) and offer[1] == want and not any_prompt
        if offer and want == 'accepts':
            ok &= not strike
        elif offer:
            ok &= (bool(strike) and offer.start() < strike.start()
                   and 'merciless attack' not in log[offer.end():])
        reason = ('roll 20: offer accepted, no strike' if want == 'accepts' else
                  'roll 1: offer refused, then strike, no merciless breach')
    elif kind in ('S2', 'M2'):
        ok = (has_prompt and not offer and strike_text not in cast
              and bool(strike) and 0 <= log.find(prompt) < strike.start())
        reason = 'fleeing-victim confirmation before cast'
    else:
        ok = bool(strike) and not offer and not any_prompt
        reason = 'area spell strikes without offer or prompt'
    red_evidence[scene] = (bool(strike) and not offer and not any_prompt
                           and 'merciless attack' in log[strike.end():])
    results[scene] = bool(ok)
    print(f'{"PASS" if ok else "FAIL"} {scene}: {reason}')
    print(f'  offer={offer[0] if offer else "none"}; prompt={any_prompt}')
    for line in log.splitlines():
        if (strike_text and strike_text in line) or 'merciless attack' in line or 'your terms' in line or prompt in line:
            print('  ' + line)

for scene in ('S1-acc', 'S1-ref', 'M1-acc', 'M1-ref', 'S2', 'M2', 'S3'):
    judge(scene)
print(f'Specimens: {out}')
if sys.argv[2:] == ['--prove-red']:
    ok = (all(not v and red_evidence[k] for k, v in results.items() if k != 'S3')
          and results['S3'])
    print('PROVE-RED ' + ('OK' if ok else 'BAD') + ': require every S1/M1/S2/M2 scene FAIL and S3 PASS')
    sys.exit(0 if ok else 1)
sys.exit(0 if all(results.values()) else 1)
