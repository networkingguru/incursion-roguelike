#!/usr/bin/env python3
"""inc-gst2: crowded-level turn-cost reproduction -- key-script generator and analyser.

  crowd_turn_cost.py keys <baseline|hostile|allies> [--rest N] > out.keys
  crowd_turn_cost.py analyse <baseline|hostile|allies> <run-dir> [--rest N]

Run it through tools/check_crowd_turn_cost.sh; read that script's header first.

THE KEY SCRIPT, in order. All three scenarios share steps 1-4, so the sweep
leaves the same map memory and the same random state in each of them.
  1. Wizard switches ON: Always Rest Safely, Ghostwalking, Freeze Monsters.
  2. Genocide, then a ghostwalk sweep of the 128x128 grid. Rows are 3 squares
     apart and the player sees every square next to him, so every floor square
     the sweep touches is remembered. The sweep spends about 5000 game turns.
  3. Genocide again (the level spawned monsters during the sweep).
  4. Ghostwalk back to the Entry Chamber, a 21x21 open cave room.
  5. HOSTILE and ALLIES only: Wizard Sight ON, summon 90 white worm masses spread over
     the room (the cursor is relative to the player) and, for ALLIES, make each
     one the player's follower; Wizard Sight OFF. The creature is a white worm
     mass: slow (Mov 30%, Speed 70%), blind, not a carnivore. A giant rat was
     tried first and does not work: rats are carnivores and eat each other.
  6. Ghostwalk west to a floor square in a room about 40 squares away.
     Ghostwalking, Freeze Monsters and Always Rest Safely go OFF there: the
     player stands on real floor, reachable by a real path, and the crowd wakes.
  7. Examine every Thing (wizard "Examine All Things"). This PROVES the crowd.
  8. @dump:start, REST x '.', @dump:end. The driver times start..end by the
     modification times of the two dump files.
  9. Examine every Thing again.

WHY THE PLAYER SURVIVES: a white worm mass moves at 30% and starts 35 to 45
squares of corridor away; nothing reaches him in 300 rests, and the result line
shows his hit points at the end. THE CROWD IS PROVEN twice from the game's own
wizard display: "Examine Nearby Things" at the arrival square (every Thing within
10 squares, one dump each, class T_MONSTER) and "Examine All Things" after the
run. The census scenario counts the squares the player remembers.
"""
import glob
import os
import re
import sys

# After every ghostwalk step: SPACE closes the "You see here" box that a pile of
# items opens (a direction key does not close it), and the @while line answers
# "no" to any "Confirm move over the ...?" prompt a found trap or sticky terrain
# raises, and a second one aborts the move at a "threatened area" prompt. Without them one box or one prompt swallows the rest of the script. A
# blind "n" would not do: in play "n" opens a rename prompt of its own.
def mv(d, n):
    return '\n'.join([d + ' SPACE\n@while "Confirm move over" n\n@while "threatened area" a'] * n)


# Wizard Mode Switches rows (src/Tables.cpp, OPT_NODEATH ... OPT_ALL_ROLLS).
SW_SAFEREST, SW_GHOST, SW_WIZSIGHT, SW_FREEZE = 4, 8, 9, 10


def toggles(*rows, menu_open=False):
    """Keys that flip the given Wizard Mode Switches rows, then leave the menu."""
    s = [] if menu_open else ['w']
    s.append('@choose "Wizard Mode Switches"')
    cur = 0
    for r in sorted(rows):
        s.append('DOWN*%d' % (r - cur))
        s.append('SPACE')
        cur = r
    s.append('ESC')
    return s


def sweep():
    s = [mv('UP', 109)]
    y = 1
    while True:
        s.append(mv('LEFT', 127))
        s.append(mv('RIGHT', 127))
        if y + 3 > 127:
            break
        s.append(mv('DOWN', 3))
        y += 3
    return s


CROWD = 90
CREATURE = 'white worm mass'   # slow (Mov 30%, Speed 70%), blind, not a carnivore, no corpse
CATEGORY = 'Worms'             # its page in the wizard summon menu
SWEEP_END = (126, 126)     # where the sweep leaves the player (checked by the census)
# Where the sweep leaves the player, relative to the arrival square, and where
# the far room is. Both come from development dumps; the driver checks them.
SWEEP_END_TO_START = ('LEFT', 15, 'UP', 16)
START_TO_FAR = ('LEFT', 37, 'DOWN', 6)
NEARBY_STEPS = 112     # 'Examine Nearby Things' (within 10 squares): the 90 rats, then 19 others, then it wraps (cycle = 109)
ALL_STEPS = 200        # 'Examine All Things': ~100 older Things, then the 90 rats, then a few more


def crowd_offsets(n):
    """n squares of the Entry Chamber around the arrival square.

    Make Player Master of Monster only finds a rat within about 8 squares by the
    game's own distance (the larger offset plus half the smaller): measured, a
    rat at (-5,-4) is taken, one at (-7,-5) or (10,2) is not. So both crowds
    use these squares, near the player but not next to him (nothing within 3).
    The rows dy -1..1 stay empty: they are the way west."""
    cand = [(dx, dy) for dy in range(-8, 9) for dx in range(-8, 9)
            if max(abs(dx), abs(dy)) + min(abs(dx), abs(dy)) // 2 <= 8
            and max(abs(dx), abs(dy)) > 3 and abs(dy) > 1]
    return [cand[i * len(cand) // n] for i in range(n)]


def cursor(dx, dy):
    k = []
    if dx:
        k.append('%s*%d' % ('RIGHT' if dx > 0 else 'LEFT', abs(dx)))
    if dy:
        k.append('%s*%d' % ('DOWN' if dy > 0 else 'UP', abs(dy)))
    return ' '.join(k)


def examine(tag, which, steps, ally_pages):
    """Browse the Thing list from the player eastward, one @dump per Thing.

    "Examine Player Data" first: it sizes the dump window; without it the Thing
    dump wraps one character per line. The second page (DOWN*30) holds the
    Target System, which names the player as a follower's summoner; every fourth crowd member
    gets it, because the engine's string queue (64000) overflows and
    crashes the game if a browse redisplays too often between map draws."""
    s = ['w', '@choose "Examine Player Data"', 'ESC', 'w', '@choose "%s"' % which]
    for i in range(steps):
        s.append('RIGHT')
        s.append('@dump:%s-%03d-a' % (tag, i))
        if ally_pages and i < CROWD and i % 4 == 0:
            s.append('DOWN*30')
            s.append('@dump:%s-%03d-b' % (tag, i))
            s.append('UP*30')
    s.append('ESC')
    return s


CENSUS_STOPS = [('LEFT', 30), ('LEFT', 64), ('UP', 31), ('RIGHT', 64), ('UP', 38),
                ('LEFT', 64), ('UP', 38), ('RIGHT', 64)]


def census_tour():
    """From the sweep's end square (126,126) walk a snake that never revisits a
    square and dump the map at 8 stops, so each dump matches one probe state."""
    s = []
    for i, (d, n) in enumerate(CENSUS_STOPS):
        s.append(mv(d, n))
        s.append('@dump:census-%d' % i)
    return s


def keys(scenario, rest):
    s = ['s', 'w y']
    s += toggles(SW_SAFEREST, SW_GHOST, SW_FREEZE, menu_open=True)
    s += ['w', '@choose "Genocide Everything"']
    s += sweep()
    s.append('@dump:swept')
    s += ['w', '@choose "Genocide Everything"']
    if scenario == 'census':
        return '\n'.join(s + census_tour()) + '\n'
    d1, n1, d2, n2 = SWEEP_END_TO_START
    s += [mv(d1, n1), mv(d2, n2)]
    s.append('@dump:start-square')
    if scenario != 'baseline':
        s += toggles(SW_WIZSIGHT)
        for dx, dy in crowd_offsets(CROWD):
            s += ['w', '@choose "Monster Summoning"', 'TAB', '@choose "%s"' % CATEGORY,
                  '@choose "%s"' % CREATURE, cursor(dx, dy) + ' ENTER']
            if scenario == 'allies':
                s += ['w', '@choose "Make Player Master of Monster"', 'l',
                      cursor(dx, dy) + ' ENTER']
        s.append('@dump:crowd-made')
        s += toggles(SW_WIZSIGHT)
        if scenario == 'hostile':
            # Each summoned rat lists the other rats as targets, and dumping 90
            # such lists overflows the engine's 64000-string queue and crashes
            # the browse. Followers keep their link to the player, so ALLIES
            # does not do this; the hostile rats re-acquire targets on their turn.
            s += ['w', '@choose "All Forget All Targets"']
    s += examine('before', 'Examine Nearby Things', NEARBY_STEPS, scenario != 'baseline')
    d1, n1, d2, n2 = START_TO_FAR
    s += [mv(d1, n1), mv(d2, n2)]
    s.append('@dump:far-square')
    s += toggles(SW_SAFEREST, SW_GHOST, SW_FREEZE)
    s.append('@dump:start')
    s.append('.*%d' % rest)
    s.append('@dump:end')
    s += examine('after', 'Examine All Things', ALL_STEPS, False)
    return '\n'.join(s) + '\n'


# ---------------------------------------------------------------- analysis

THING = re.compile(r"'(.)' -- #(\d+): (.*?) \(class (\w+)")
XY = re.compile(r"X:(\d+) Y:(\d+)")


def read_things(run, tag):
    """[(index, name, class, x, y, follows_player)] from the examine dumps."""
    out = []
    for f in sorted(glob.glob('%s/logs/screens/*-%s-???-a.txt' % (run, tag))):
        L = open(f).read().split('\n')
        head = ' '.join(l[:64].strip() for l in L[1:9])
        m = THING.search(head)
        if not m:
            continue
        xy = XY.search(head)
        ally = None
        pat = f.rsplit('/', 1)[0] + '/*-%s-%s-b.txt' % (tag, f.rsplit('-', 2)[1])
        for bf in glob.glob(pat):
            B = ' '.join(l[:64] for l in open(bf).read().split('\n'))
            ally = ('as its summoner' in B) or ('NO_PHD' in B)
        out.append((int(m.group(2)), m.group(3), m.group(4),
                    int(xy.group(1)) if xy else -1, int(xy.group(2)) if xy else -1, ally))
    return out


def stamp(path):
    return int(open(path).readline().split('turn')[1].split('=')[0])


def is_rat(t):
    return t[1].endswith(CREATURE) and t[2] == 'T_MONSTER'


def census(run):
    """Known squares of the whole level, from the 8 census dumps (needs
    INCURSION_MAP_PROBE=1 for the window offsets). Prints and returns counts."""
    states = []
    for l in open(run + '/logs/mapprobe.log'):
        m = re.search(r'player=\((\d+),(\d+)\) offset=\((\d+),(\d+)\)', l)
        if m:
            t = tuple(map(int, m.groups()))
            if not states or states[-1] != t:
                states.append(t)
    # The tour starts at the sweep's end square and never revisits a square, so
    # only the states from the LAST visit to it onward can match a census dump.
    ends = [i for i, t in enumerate(states) if (t[0], t[1]) == SWEEP_END]
    if not ends:
        print('FAIL: census: the player never stood on the sweep end square %s' % (SWEEP_END,))
        return None
    states = states[ends[-1]:]
    grid = {}
    for f in sorted(glob.glob(run + '/logs/screens/*-census-?.txt')):
        rows = open(f).read().split('\n')[5:5 + 38]
        at = None
        for ry, r in enumerate(rows):
            r = r.ljust(80)[:64]
            if '@' in r:
                at = (r.index('@'), ry)
        k = int(f.rsplit('-', 1)[1].split('.')[0])
        px, py = SWEEP_END
        for d, n in CENSUS_STOPS[:k + 1]:
            px += {'LEFT': -n, 'RIGHT': n}.get(d, 0)
            py += {'UP': -n, 'DOWN': n}.get(d, 0)
        cands = [t for t in states if (t[0], t[1]) == (px, py) and (t[0] - t[2], t[1] - t[3]) == at]
        if len(cands) != 1:
            print('FAIL: census %s: %d probe states match the player square' % (f, len(cands)))
            return None
        ox, oy = cands[0][2], cands[0][3]
        for ry, r in enumerate(rows):
            r = r.ljust(80)[:64]
            for rx, c in enumerate(r):
                if c != ' ':
                    grid[(ox + rx, oy + ry)] = c
    known = len(grid)
    passable = sum(1 for c in grid.values() if c not in '#')
    xs = [k[0] for k in grid]
    ys = [k[1] for k in grid]
    print('CENSUS known_squares=%d passable_known=%d walls_known=%d extent=x%d..%d y%d..%d'
          % (known, passable, known - passable, min(xs), max(xs), min(ys), max(ys)))
    return grid


def analyse(scenario, run, rest):
    if scenario == 'census':
        return 0 if census(run) else 2
    scr = '%s/logs/screens' % run
    one = lambda pat: sorted(glob.glob('%s/*-%s.txt' % (scr, pat)))
    for need in ('start', 'end', 'far-square', 'swept'):
        if not one(need):
            print('FAIL: %s: no %s dump in %s' % (scenario, need, scr))
            return 2
    start, end = one('start')[0], one('end')[0]
    ticks = stamp(end) - stamp(start)
    wall = os.stat(end).st_mtime - os.stat(start).st_mtime
    before = read_things(run, 'before')
    after = read_things(run, 'after')
    seen, uniq = set(), []
    for t in before:
        if t[0] not in seen:
            seen.add(t[0])
            uniq.append(t)
    before_all = before
    before = uniq
    rats = [t for t in before if is_rat(t)]
    rats_after = [t for t in after if is_rat(t)]
    want = 0 if scenario == 'baseline' else CROWD
    ok = True
    idx = [t[0] for t in before_all]
    if not any(b < a for a, b in zip(idx, idx[1:])):
        print('FAIL: %s: the Thing list never wrapped; raise EXAMINE_ALL' % scenario)
        ok = False
    if len(rats) != want:
        print('FAIL: %s: proved %d %s, wanted %d' % (scenario, len(rats), CREATURE, want))
        ok = False
    sampled = [t for t in rats if t[5] is not None]
    followers = [t for t in sampled if t[5]]
    if scenario != 'baseline' and len(sampled) < 20:
        print('FAIL: %s: only %d crowd members have a second page to read' % (scenario, len(sampled)))
        ok = False
    if scenario == 'allies' and len(followers) != len(sampled):
        print('FAIL: allies: %d of %d sampled crowd members name the player as summoner'
              % (len(followers), len(sampled)))
        ok = False
    if scenario == 'hostile' and followers:
        print('FAIL: hostile: %d sampled crowd members name the player as summoner' % len(followers))
        ok = False
    if ticks <= 0 or wall <= 0:
        print('FAIL: %s: no elapsed time (ticks %d, wall %.3f)' % (scenario, ticks, wall))
        ok = False
    turns = ticks / 16.0          # one '.' costs 16 game ticks here (measured: 10 rests = 160)
    if abs(turns - rest) > 0.1 * rest:
        print('FAIL: %s: %d rests advanced %.1f turns' % (scenario, rest, turns))
        ok = False
    spread = ''
    if rats:
        spread = ' crowd_x=%d..%d crowd_y=%d..%d' % (
            min(t[3] for t in rats), max(t[3] for t in rats),
            min(t[4] for t in rats), max(t[4] for t in rats))
    hp = re.findall(r'HP:(-?\d+)/(\d+)', open(end).read())
    hp = '%s/%s' % hp[-1] if hp else 'unknown'
    print('RESULT %s crowd=%d followers_of_sampled=%d/%d crowd_after=%d monsters_before=%d monsters_after=%d '
          'player_hp_at_end=%s turns=%.0f ticks=%d wall=%.3fs ms_per_turn=%.2f%s'
          % (scenario, len(rats), len(followers), len(sampled), len(rats_after),
             sum(1 for t in before if t[2] == 'T_MONSTER'),
             sum(1 for t in after if t[2] == 'T_MONSTER'),
             hp, turns, ticks, wall, 1000.0 * wall / max(turns, 1), spread))
    return 0 if ok else 2


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    rest = 300
    if '--rest' in argv:
        rest = int(argv[argv.index('--rest') + 1])
    if argv[1] == 'keys':
        sys.stdout.write(keys(argv[2], rest))
        return 0
    if argv[1] == 'analyse':
        return analyse(argv[2], argv[3], rest)
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
