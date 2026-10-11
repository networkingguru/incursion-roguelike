#!/bin/bash
# gate: live
# Reproduction for bd inc-a7jq (the loot claim). Expected RED for A and B on
# the unfixed build, GREEN for C before and after the feature.
#
#   BACKEND=posix ./build_macos.sh
#   tools/check_loot_claim.sh
#
# A  a non-hostile creature must not take a drop of the player's kill while the
#    player stands in the room and sees the drop.
# B  a hostile orc takes a drop of the player's kill while the claim is live,
#    then flees (Cause Fear). Attacking it must raise no fleeing-victim prompt
#    and no "guilty" penalty for the Lawful Good paladin.
# B0 control: the same fleeing orc holding no claimed item. The prompt or the
#    penalty MUST still appear, before and after the feature.
# C  control: a drop that is NOT from a party kill is still taken. It proves the
#    reading in A sees a real pickup in the same arrangement.
#
# Every verdict reads the engine's own screen: the sidebar's "Things in View"
# (which items lie on the floor), the message line, the message log, and the
# Wizard Mode Switches screen (to prove Freeze Monsters was in the state each
# step assumed). A scenario that cannot establish its own precondition reports
# INCONCLUSIVE, never PASS.
#
# Exit 0 = all PASS, 1 = at least one FAIL, 2 = no FAIL but one INCONCLUSIVE.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SEED=4
OPTS=tools/fixtures/options-2026-08-22-noroomdesc.dat
CHAR=tools/fixtures/chars/human-paladin-seed4-opt0822.sav
STAMP="$(date +%Y%m%d-%H%M%S)-$$"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: build first with BACKEND=posix ./build_macos.sh"
    exit 2
}
unset INCURSION_BIN INCURSION_LAUNCHER

DIRS=()
for name in a-nonhostile-pickup b-thief-attack b0-fleeing-control c-control d-claim-ends; do
    RUN="logs/runs/lootclaim-$name-$STAMP"
    INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$CHAR" INCURSION_RUN_DIR="$RUN" \
        tools/headless.sh "tools/keys/lootclaim-$name.keys" "$SEED" \
        > "$RUN.out" 2>&1
    echo "$? $name $RUN"
    DIRS+=("$RUN")
done > "logs/runs/lootclaim-$STAMP.status"

python3 -I - "logs/runs/lootclaim-$STAMP.status" <<'PY'
import re, sys
from pathlib import Path

status = {}
for line in Path(sys.argv[1]).read_text().split('\n'):
    if line.strip():
        code, name, run = line.split()
        status[name.split('-')[0].upper()] = (int(code), Path(run) / 'logs' / 'screens', run)

results = {}   # letter -> (verdict, text)

def screen(letter, label):
    code, scr, _ = status[letter]
    hits = list(scr.glob('*-' + label + '.txt'))
    if len(hits) != 1:
        raise ValueError('no screen dump named ' + label)
    return hits[0].read_text().split('\n')[1:]

def top(lines):
    return lines[0].split('|')[0].strip()

def sidebar(lines):
    return [l.split('|', 1)[1].rstrip() if '|' in l else '' for l in lines]

def things(lines):
    out, on = [], False
    for s in sidebar(lines):
        if s.startswith('Things in View'):
            on = True
        elif on and s.startswith('['):
            break
        elif on:
            out.append(s.strip())
    return out

def floor_items(lines):
    return sorted(m[1] for t in things(lines)
                  for m in [re.match(r'^[*&] \? (.+)$', t)] if m)

def has_creature(lines, word):
    return any(re.match(r'^[a-zA-Z*&] ' + word, t) for t in things(lines))

def xp(lines):
    for s in sidebar(lines):
        m = re.match(r'(\d+)/\d+ XP', s)
        if m:
            return int(m[1])
    raise ValueError('no XP line in the sidebar')

def logtext(lines):
    parts = []
    for line in lines:
        f = line.split('|')
        if len(f) >= 3:
            parts.append(''.join(f[1:-1]))
    return ' '.join(' '.join(parts).split())

def freeze(letter, label, want):
    row = [l for l in screen(letter, label) if 'Freeze Monsters' in l]
    if len(row) != 1:
        raise ValueError(label + ': no Freeze Monsters row')
    if not re.search(r'Freeze Monsters\s+' + want + r'\b', row[0]):
        raise ValueError(label + ': Freeze Monsters is not ' + want)

def session_ok(letter):
    code, _, run = status[letter]
    if code != 0:
        raise ValueError('headless session exited %d (see %s.out)' % (code, run))

def baseline(letter):
    killed = screen(letter, 'killed')
    items = floor_items(killed)
    if not items:
        raise ValueError('no "? item" on the floor in the "killed" dump')
    if not has_creature(killed, 'human'):
        raise ValueError('the human is not in view in the "killed" dump')
    return killed, items

def pickup_scenario(letter, expect_taken):
    session_ok(letter)
    freeze(letter, 'freeze-on', 'YES')
    freeze(letter, 'freeze-off', 'NO')
    killed, items = baseline(letter)
    waited = screen(letter, 'waited')
    if letter == 'A' and xp(killed) == 0:
        raise ValueError('the kobold was not killed by the player (XP still 0)')
    if not has_creature(waited, 'human') and not any('human' in t for t in things(waited)):
        raise ValueError('the human is not in view after the wait')
    left = floor_items(waited)
    gone = [i for i in items if i not in left]
    log = logtext(screen(letter, 'log'))
    pickups = re.findall(r'A human picks up an? \S* ?[^.]*\.', log)
    return items, gone, pickups

# ---- A -------------------------------------------------------------------
try:
    items, gone, pickups = pickup_scenario('A', False)
    ev = 'floor after the kill: %s; gone after 10 turns: %s; log: %s' % (
        items, gone or 'none', pickups or 'no pickup message')
    if gone or pickups:
        results['A'] = ('FAIL', 'a non-hostile human took a drop of the player\'s kill with the player in the room. ' + ev)
    else:
        results['A'] = ('PASS', 'the drops of the player\'s kill stayed on the floor. ' + ev)
except ValueError as e:
    results['A'] = ('INCONCLUSIVE', str(e))

# ---- C -------------------------------------------------------------------
try:
    items, gone, pickups = pickup_scenario('C', True)
    ev = 'floor before: %s; gone after 10 turns: %s; log: %s' % (
        items, gone or 'none', pickups or 'no pickup message')
    if gone and pickups:
        results['C'] = ('PASS', 'a non-hostile human took a drop that was not from a party kill. ' + ev)
    else:
        results['C'] = ('FAIL', 'the control drop was not taken, so A reads nothing. ' + ev)
except ValueError as e:
    results['C'] = ('INCONCLUSIVE', str(e))

# ---- B and B0 --------------------------------------------------------------
def orc_scenario(letter, thief):
    session_ok(letter)
    freeze(letter, 'switches-1', 'YES')
    if thief:
        freeze(letter, 'switches-2', 'NO')
        freeze(letter, 'switches-3', 'YES')
    killed = screen(letter, 'killed')
    items = floor_items(killed)
    if not items:
        raise ValueError('no "? item" on the floor in the "killed" dump')
    if xp(killed) == 0:
        raise ValueError('the kobold was not killed by the player (XP still 0)')
    left = floor_items(screen(letter, 'taken'))
    took = [i for i in items if i not in left]
    fear = logtext(screen(letter, 'fearlog')) + ' ' + logtext(screen(letter, 'log'))
    if thief:
        if not took or not re.search(r'black orc picks up', fear):
            raise ValueError('the hostile orc took nothing from the kill (floor %s, taken %s)' % (items, took))
    elif took:
        raise ValueError('the control orc took an item %s' % took)
    if 'seems terrified' not in fear:
        raise ValueError('the orc was never frightened ("seems terrified" not in the log)')
    adj = screen(letter, 'adjacent')
    if not any('o@' in l.split('|')[0] for l in adj):
        raise ValueError('the paladin is not next to the orc')
    attack = screen(letter, 'attack')
    prompt = [t for t in (l.split('|')[0].strip() for l in attack)
              if t.startswith('Confirm attack')]
    log = logtext(screen(letter, 'log'))
    guilty = re.findall(r'You feel guilty \([^)]*\)', log)
    hit = re.search(r'(hitting|missing|killing|slaying)[^.]*the (black )?or', top(attack) + ' ' + log)
    ev = 'orc %s; prompt: %s; penalty: %s' % (
        'took ' + str(took) if thief else 'took nothing', prompt or 'none', guilty or 'none')
    return prompt, guilty, hit, ev

try:
    prompt, guilty, hit, ev = orc_scenario('B', True)
    if prompt or guilty:
        results['B'] = ('FAIL', 'attacking a fleeing orc that holds a drop of the player\'s kill raised an alignment prompt/penalty. ' + ev)
    elif hit:
        results['B'] = ('PASS', 'the fleeing thief was attacked with no prompt and no penalty. ' + ev)
    else:
        raise ValueError('no prompt, but no attack on the orc is visible either. ' + ev)
except ValueError as e:
    results['B'] = ('INCONCLUSIVE', str(e))

try:
    prompt, guilty, hit, ev = orc_scenario('B0', False)
    if prompt or guilty:
        results['B0'] = ('PASS', 'a fleeing orc with no claimed item still raises the fleeing-victim prompt/penalty. ' + ev)
    else:
        results['B0'] = ('FAIL', 'no prompt or penalty for attacking an ordinary fleeing orc, so B reads nothing. ' + ev)
except ValueError as e:
    results['B0'] = ('INCONCLUSIVE', str(e))

# ---- D -------------------------------------------------------------------
# A broken build whose claim never ends leaves the drops on the floor, so
# "gone" is empty and D FAILs; one that carries the claim into the pickup makes
# the human a thief, so the bump-confirm prompt is missing and D FAILs.
try:
    session_ok('D')
    freeze('D', 'switches-1', 'YES')
    freeze('D', 'switches-2', 'NO')
    freeze('D', 'switches-3', 'YES')
    killed, items = baseline('D')
    if xp(killed) == 0:
        raise ValueError('the kobold was not killed by the player (XP still 0)')
    outside = screen('D', 'outside')
    seen = [i for i in items if i in floor_items(outside)]
    if seen:
        raise ValueError('the player still sees the drops from outside: %s' % seen)
    back = screen('D', 'back')
    gone = [i for i in items if i not in floor_items(back)]
    attack = screen('D', 'attack')
    prompt = [t for t in (l.split('|')[0].strip() for l in attack)
              if t.startswith('Confirm attack the human')]
    declined = screen('D', 'declined')
    if not any('Confirm attack' in l.split('|')[0] for l in attack):
        raise ValueError('no attack prompt and no attack was captured')
    ev = 'floor after the kill: %s; gone after the player returned: %s; prompt: %s' % (
        items, gone or 'none', prompt or 'none')
    if not gone:
        results['D'] = ('FAIL', 'the claim never ended: the human did not take the drops while the player was out of view. ' + ev)
    elif not prompt:
        results['D'] = ('FAIL', 'the human took the drops after the claim ended but is treated as a thief (no confirm prompt). ' + ev)
    else:
        results['D'] = ('PASS', 'the human took the drops once the player was away and is no thief: the confirm prompt still appears. ' + ev)
except ValueError as e:
    results['D'] = ('INCONCLUSIVE', str(e))

names = {'A': 'A non-hostile pickup of a party-kill drop',
         'B': 'B attack on the fleeing thief, Lawful Good',
         'B0': 'B0 control, fleeing orc holding no claimed item',
         'D': 'D claim ends when the player leaves',
         'C': 'C control, drop not from a party kill'}
for k in ['A', 'B', 'B0', 'C', 'D']:
    v, t = results[k]
    print('%s: %s -- %s' % (v, names[k], t))
print('specimens: ' + ', '.join(status[k][2] for k in ['A', 'B', 'B0', 'C', 'D']))
verdicts = [results[k][0] for k in ['A', 'B', 'B0', 'C', 'D']]
sys.exit(1 if 'FAIL' in verdicts else 2 if 'INCONCLUSIVE' in verdicts else 0)
PY
