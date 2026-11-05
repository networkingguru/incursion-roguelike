#!/bin/bash
# gate: live
# inc-h5aql phase 1: four-set Exchange and sheathing AoO, red before implementation.
# fact: character, stats, feats, names, defaults, gear and equipment slots -- INCURSION_LOAD=tools/fixtures/chars/weapon-sets-old-defaults.sav
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: terrain and starting position -- saved map in the character fixture
# fact: no other monsters -- wizard Genocide Everything in the fixture recipe
# fact: monster position -- wizard Monster Summoning, one goblin one square east
# fact: hostility -- wizard All Monster Aggravate
# fact: monster remains adjacent; no normal AI attacks -- fixture's wizard Freeze Monsters switch
# fact: monster gear -- INCURSION_SUMMON_NO_GEAR=1
# fact: available AoO -- eight Wait One Turn commands cross the global 60-segment refill
# fact: attack misses (no damage, death or damage-triggered state changes) -- INCURSION_LOF_FORCE_ROLL=1
# fact: enemy can perceive and take an AoO on this player -- same-position positive control withdrawing a pack item, recorded by INCURSION_TRIP_AOO_PROBE
# fact: accepted AoO count and actor/victim -- INCURSION_TRIP_AOO_PROBE, bounded by screen-dump turn stamps
# fact: wielded item and offhand after Exchange -- inventory screen dumps; names fixed by fixture
# fact: AC10 items (sword, dagger, longspear, bow, knife, kite shield, shotputs) -- the fixture's own gear
# fact: saved handles -- dump_save.sh "Weapon Sets" section of the real save reader, not a screen
# fact: AC1-AC6 gear -- weapon-sets-four-setup.keys moves the sword to the pack and puts dagger (M) and knife (S) on the belt; the fixture's bow (R) and longspear (X) stay on the shoulders
# fact: AC2-AC6 monster position -- summon cursor keys, proved by the monster-placed map dump (@g adjacent, @.g two east, @# wall)
# fact: AC3 reach weapon -- wizard Item Acquisition dire flail (WT_REACH and WT_STRIKE_NEAR), proved by the flail-set dump
# fact: AC5 unperceived enemy -- a goblin two squares east behind a Dungeon Wall the script builds (wizard Change terrain type), proved by the map dump showing the wall and no goblin
# fact: AC6 grapple -- bare-handed Grapple command, hit forced by INCURSION_LOF_FORCE_ROLL=20, proved by the "you grab" message in grapple-target
# fact: AC6 time -- the turn stamps of the held-step1 and held-message dumps
# fact: stow slots -- a Medium character holds big weapons only on the two shoulders, so AC1-AC5 keep the sword in the pack and use belt-sized M and S; each scenario runs at most 4 presses
# fact: BARE character -- INCURSION_LOAD=tools/fixtures/chars/lizardfolk-monk-seed1.sav (Unarmed Strike), its quarterstaff dropped and potions packed by the script, bow acquired by wizard Item Acquisition
# fact: CROWDED slots -- the bow, the longspear and a wielded dire flail fit no belt, and two shoulders hold two of them, so a swap must refuse; proved by the setup-done dump
# fact: LOADOUT -- the sword rides a belt under the inc-h5aql belt rule; proved by the setup-done dump
# fact: items on the floor -- an item is on the floor when the inventory screen no longer lists it; the check lists all five weapons at every step
# fact: key actions and measurement boundaries -- checked inventory screens and @dump in weapon-sets-*.keys
# AC10 configures every set that the fixture's Medium character can fill; X has no
# one-handed reach weapon to take an off-hand item, so X off-hand must stay (none).
# AC8 measures '-' with a weapon held (aoo), then '-' from an empty hand, the C-menu forced
# switch and an inventory take-off (aoo2). An AoO is stamped with the turn of the action's
# before-dump, so each action owns the window [before-dump turn, after-dump turn).
# fact: AC7 menu contents -- dumps of the open C menu and its submenu (weapon-sets-menu.keys,
#       weapon-sets-menunone.keys); the menunone defaults are switched off by their own keys
# fact: AC7(c) grapple -- same Grapple command as AC6, hit forced by INCURSION_LOF_FORCE_ROLL=20
# fact: AC8(b)(c)(d) goblin and refill -- same summon, aggravate and eight waits as AC8(a);
#       the positive control withdraws a pack item in the same session
# fact: AC8(e) Faster Than The Eye -- wizard Item Acquisition Gauntlets of Legerdemain worn (weapon-sets-aooftte.keys), proved by the worn-gauntlets inventory dump; the same goblin provokes once they are off
# Usage: tools/check_weapon_sets.sh [seed]
#        tools/check_weapon_sets.sh --make-fixture [--force]
# Exit 1: measured failure; 2: unmeasured (including phase TODOs); 0: all pass.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
mkdir -p logs/weapon-sets
OUT="$(mktemp -d "$ROOT/logs/weapon-sets/run.XXXXXX")" || exit 2
OPTS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/weapon-sets-old-defaults.sav
if [ "${1:-}" = --make-fixture ]; then
    # make_char_fixture makes TWO sessions. Set a distinct explicit run directory
    # for each without changing the shared helper or reusing one sandbox.
    cat > "$OUT/fixture-env.sh" <<'ENV'
function tools/headless.sh() {
    local run
    run="$(mktemp -d "$WEAPON_SETS_FIXTURE_OUT/session.XXXXXX")" || return 2
    INCURSION_RUN_DIR="$run" command tools/headless.sh "$@"
}
ENV
    shift
    WEAPON_SETS_FIXTURE_OUT="$OUT" BASH_ENV="$OUT/fixture-env.sh" \
        INCURSION_LOAD=tools/fixtures/chars/dequ-save-message-seed5-opt0822.sav \
        tools/make_char_fixture.sh weapon-sets-old-defaults \
        tools/keys/weapon-sets-fixture.keys 1 "$OPTS" "$@" > "$OUT/make-fixture.out" 2>&1
    rc=$?
    cat "$OUT/make-fixture.out"
    echo "Specimens: $OUT"
    exit "$rc"
fi
SEED="${1:-1}"
for scenario in old cycle aoo aooftte aoo2 menu menunone forced adjacent crowded crowdedfree loadout loadoutadj flail distant unseen grapple; do
    ROLL=1
    [ "$scenario" = grapple ] && ROLL=20
    [ "$scenario" = forced ] && ROLL=20
    INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$FIXTURE" \
        INCURSION_RUN_DIR="$OUT/$scenario" \
        INCURSION_TRIP_AOO_PROBE=1 INCURSION_SUMMON_NO_GEAR=1 \
        INCURSION_LOF_FORCE_ROLL="$ROLL" \
        tools/headless.sh "tools/keys/weapon-sets-$scenario.keys" "$SEED" \
        > "$OUT/$scenario.out" 2>&1
    echo "$?" > "$OUT/$scenario.status"
done
# BARE: a Monk has no melee weapon set, so bare hands are M. Own character fixture.
INCURSION_OPTIONS="$OPTS" INCURSION_LOAD=tools/fixtures/chars/lizardfolk-monk-seed1.sav \
    INCURSION_RUN_DIR="$OUT/bare" INCURSION_SUMMON_NO_GEAR=1 INCURSION_LOF_FORCE_ROLL=1 \
    tools/headless.sh tools/keys/weapon-sets-bare.keys "$SEED" > "$OUT/bare.out" 2>&1
echo "$?" > "$OUT/bare.status"
# AC10: configure the sets with the inventory-screen keys and save; load that save,
# save again; read the handles of both saves through the save reader.
INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$FIXTURE" INCURSION_RUN_DIR="$OUT/configure" \
    INCURSION_SUMMON_NO_GEAR=1 tools/headless.sh tools/keys/weapon-sets-configure.keys "$SEED" \
    > "$OUT/configure.out" 2>&1
echo "$?" > "$OUT/configure.status"
CONF_SAVE="$(ls "$OUT"/configure/save/*.sav 2>/dev/null | grep -v weapon-sets-old-defaults | head -1)"
if [ -n "$CONF_SAVE" ]; then
    INCURSION_DUMP_SANDBOX="$OUT/dump-configure" tools/dump_save.sh "$CONF_SAVE" \
        > "$OUT/configure.dump" 2>&1
    INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$CONF_SAVE" INCURSION_RUN_DIR="$OUT/reload" \
        INCURSION_SUMMON_NO_GEAR=1 tools/headless.sh tools/keys/weapon-sets-reload.keys "$SEED" \
        > "$OUT/reload.out" 2>&1
    echo "$?" > "$OUT/reload.status"
    RELOAD_SAVE="$(ls "$OUT"/reload/save/*.sav 2>/dev/null | grep -v "$(basename "$CONF_SAVE")\$" | head -1)"
    [ -z "$RELOAD_SAVE" ] && RELOAD_SAVE="$OUT/reload/save/$(basename "$CONF_SAVE")"
    if [ -f "$RELOAD_SAVE" ]; then
        INCURSION_DUMP_SANDBOX="$OUT/dump-reload" tools/dump_save.sh "$RELOAD_SAVE" \
            > "$OUT/reload.dump" 2>&1
    fi
fi
python3 - "$OUT" <<'PY'
from pathlib import Path
import re
import sys
root = Path(sys.argv[1])
results = {i: ('UNMEASURED', f'TODO phase {5 if i == 7 else 2 if i == 10 else 4}')
           for i in range(1, 11)}
results[11] = results[12] = results[13] = results[14] = results[15] = ('UNMEASURED', 'not run')
LABEL = {11: 'BARE', 12: 'CROWDED', 13: 'CROWDEDFREE', 14: 'LOADOUT', 15: 'LOADOUTADJ'}

class Unmeasured(Exception):
    pass

class Lost(Exception):
    pass

def screen(scenario, tag):
    rc = int((root / f'{scenario}.status').read_text())
    if rc not in (0, 3):
        raise Unmeasured(f'{scenario} session exit {rc}; see {scenario}.out')
    paths = list((root / scenario / 'logs/screens').glob(f'*-{tag}.txt'))
    if len(paths) != 1:
        raise Unmeasured(f'missing or ambiguous {tag} dump')
    text = paths[0].read_text(errors='replace')
    stamp = re.search(r'^=== screen .* mode 3  turn (\d+) ===', text)
    if not stamp or 'SPACE:Swap' not in text:
        raise Unmeasured(f'{tag} is not a stamped inventory screen')
    return text, int(stamp[1])

def slot(text, letter, label):
    match = re.search(rf'{letter}\){label}\s*:\s*(.*?)\s+(?:[0-9.]+s)?\|', text)
    if not match:
        raise Unmeasured(f'missing {label} row')
    return match[1].strip()

def hands(text):
    return slot(text, 'b', 'Weapon Hand'), slot(text, 'a', 'Ready Hand')

def assess(ac, fn):
    try:
        passed, detail = fn()
        results[ac] = ('PASS' if passed else 'FAIL', detail)
    except Lost as err:
        results[ac] = ('FAIL', str(err))
    except (Unmeasured, OSError, ValueError) as err:
        results[ac] = ('UNMEASURED', str(err))

def old():
    frames = [screen('old', t) for t in ('old-start', 'old-ranged', 'old-melee')]
    actual = [hands(t) for t, _ in frames]
    expected = [('long sword', 'orcish dagger'), ('short bow', 'short bow'),
                ('long sword', 'orcish dagger')]
    if actual[0] != expected[0]:
        raise Unmeasured(f'old fixture did not start with sword + dagger: {actual[0]}')
    return actual == expected, f'inventory hands {actual}'

def mapscreen(scenario, tag):
    rc = int((root / f'{scenario}.status').read_text())
    if rc not in (0, 3):
        raise Unmeasured(f'{scenario} session exit {rc}; see {scenario}.out')
    paths = list((root / scenario / 'logs/screens').glob(f'*-{tag}.txt'))
    if len(paths) != 1:
        raise Unmeasured(f'missing or ambiguous {tag} dump')
    text = paths[0].read_text(errors='replace')
    stamp = re.search(r'^=== screen .* mode 2  turn (\d+) ===', text)
    if not stamp:
        raise Unmeasured(f'{tag} is not a stamped map screen')
    return text, int(stamp[1])

def mainhands(scenario, tags):
    return [hands(screen(scenario, t)[0])[0] for t in tags]

STEPS = ('step1', 'step2', 'step3', 'step4')
STEPS6 = STEPS + ('step5', 'step6')
WEAPONS = ('short bow', 'orcish longspear', 'long sword', 'orcish dagger', 'orcish knife +1')

def all_held(scenario, tags, weapons=WEAPONS):
    for t in tags:
        text, _ = screen(scenario, t)
        missing = [w for w in weapons if w not in text]
        if missing:
            raise Lost(f'{t}: not in the inventory, so on the floor or lost: {missing}')
BOW, SPEAR, DAGGER, KNIFE = 'short bow', 'orcish longspear', 'orcish dagger', 'orcish knife +1'

def cycle():
    configured, _ = screen('cycle', 'setup-done')
    if (slot(configured, 'e', r'L\. Shoulder') != SPEAR
            or slot(configured, 'f', r'R\. Shoulder') != 'short bow'
            or slot(configured, 't', 'On Belt') != KNIFE
            or slot(configured, 'u', 'On Belt') != DAGGER
            or hands(configured) != ('Empty', 'Empty')):
        raise Unmeasured('cycle setup did not place R, X, M and S in their equipment slots')
    tags = ('cycle-r', 'cycle-x', 'cycle-m', 'cycle-s', 'cycle-wrap')
    actual = mainhands('cycle', tags)
    expected = [BOW, SPEAR, DAGGER, KNIFE, BOW]
    return actual == expected, 'no enemy; main hand: ' + ' -> '.join(actual)

def place(scenario, pattern, what):
    text, _ = mapscreen(scenario, 'monster-placed')
    rows = [l.split('|')[0] for l in text.splitlines()[1:]]
    if not any(re.search(pattern, r) for r in rows):
        raise Unmeasured(f'monster control failed: {what} not on the map')

def adjacent():
    place('adjacent', r'@g', 'goblin one square east')
    actual = mainhands('adjacent', STEPS6)
    all_held('adjacent', STEPS6)
    return actual == [BOW, DAGGER, KNIFE, BOW, DAGGER, KNIFE], \
        'goblin adjacent, reach-only X; main hand: ' + ' -> '.join(actual)

def crowd(scenario, expected, goblin):
    if goblin:
        place(scenario, r'@g', 'goblin one square east')
    setup, t_prev = screen(scenario, 'setup-done')
    if hands(setup)[0] != 'dire flail':
        raise Unmeasured('the dire flail is not wielded at the start')
    actual = mainhands(scenario, STEPS6)
    all_held(scenario, STEPS6, WEAPONS + ('dire flail',))
    prev, outcome = setup, []
    for n in range(1, 7):
        msg, tm = mapscreen(scenario, f'msg{n}')
        line = msg.splitlines()[1].split('|')[0]
        cur, tcur = screen(scenario, f'step{n}')
        refused = 'nowhere to put away' in line
        shoulders_full = all(slot(prev, c, lbl) != 'Empty'
                             for c, lbl in (('e', r'L\. Shoulder'), ('f', r'R\. Shoulder')))
        if refused and (tm != t_prev or not shoulders_full):
            return False, f'press {n}: refused ("{line.strip()}") with a free shoulder or after spending time'
        if not refused and (tm <= t_prev or 'fumble' in line):
            return False, f'press {n}: no refusal but no swap either ("{line.strip()}")'
        outcome.append('refused' if refused else 'swapped')
        prev, t_prev = cur, tcur
    return actual == expected[0] and outcome == expected[1], \
        'main hand: ' + ' -> '.join(actual) + '; ' + ', '.join(outcome) + \
        '; a refusal only when both shoulders are full and no time passes; nothing lost'

def crowded():
    return crowd('crowded', ([BOW] * 6, ['swapped'] + ['refused'] * 5), True)

def crowdfree():
    return crowd('crowdedfree', ([BOW, SPEAR] + [SPEAR] * 4, ['swapped', 'swapped'] + ['refused'] * 4), False)

def loadout(goblin, expected):
    if goblin:
        place('loadoutadj', r'@g', 'goblin one square east')
    name = 'loadoutadj' if goblin else 'loadout'
    setup, _ = screen(name, 'setup-done')
    if (slot(setup, 'e', r'L\. Shoulder') != SPEAR or slot(setup, 'f', r'R\. Shoulder') != 'short bow'
            or {slot(setup, 't', 'On Belt'), slot(setup, 'u', 'On Belt')} != {'long sword', DAGGER}):
        raise Lost('loadout: the sword or dagger did not reach a belt slot (the belt refused it)')
    actual = mainhands(name, STEPS6)
    all_held(name, STEPS6)
    for n in range(1, 7):
        line = mapscreen(name, f'msg{n}')[0].splitlines()[1]
        if 'nowhere' in line or 'fumble' in line:
            return False, f'press {n} refused: "{line.split("|")[0].strip()}"'
    return actual == expected, 'main hand: ' + ' -> '.join(actual) + '; no refusal, nothing lost'

def loadout_free():
    return loadout(False, [BOW, SPEAR, 'long sword', DAGGER, BOW, SPEAR])

def loadout_adj():
    return loadout(True, [BOW, 'long sword', DAGGER, BOW, 'long sword', DAGGER])

def bare():
    place('bare', r'@g', 'goblin one square east')
    actual = mainhands('bare', STEPS)
    return actual == [BOW, 'Empty', BOW, 'Empty'], \
        'Monk, R = bow, M = bare hands, goblin adjacent; main hand: ' + ' -> '.join(actual)

def flail():
    place('flail', r'@g', 'goblin one square east')
    text, _ = screen('flail', 'flail-set')
    if slot(text, 'e', r'L\. Shoulder') != 'dire flail':
        raise Unmeasured('X is not the dire flail')
    actual = mainhands('flail', STEPS)
    return actual == [BOW, 'dire flail', DAGGER, KNIFE], \
        'goblin adjacent, X = dire flail; main hand: ' + ' -> '.join(actual)

def distant():
    place('distant', r'@\.g', 'goblin two squares east')
    actual = mainhands('distant', STEPS)
    return actual == [BOW, SPEAR, BOW, SPEAR], \
        'goblin two squares east; main hand: ' + ' -> '.join(actual)

def unseen():
    place('unseen', r'@#\.', 'wall one square east and no goblin shown behind it')
    actual = mainhands('unseen', STEPS)
    return actual == [BOW, SPEAR, DAGGER, KNIFE], \
        'goblin two squares east behind a wall; main hand: ' + ' -> '.join(actual)

def grapple():
    text, t0 = mapscreen('grapple', 'grapple-target')
    if 'you grab' not in text.splitlines()[1]:
        raise Unmeasured('the grapple did not start')
    s1, t1 = screen('grapple', 'held-step1')
    msg, t2 = mapscreen('grapple', 'held-message')
    s2, t3 = screen('grapple', 'held-step2')
    first, second = hands(s1)[0], hands(s2)[0]
    line = msg.splitlines()[1].split('|')[0].strip()
    ok = (first == KNIFE and t1 > t0 and second == KNIFE and t2 == t1 == t3
          and line.startswith('None of your other weapon sets'))
    return ok, (f'grappling: first "-" gives {first} (turn {t0} -> {t1}); second "-" '
                f'keeps {second}, turn {t1} -> {t2}, message "{line}"')

def aoo():
    before, start = screen('aoo', 'aoo-before')
    after, end = screen('aoo', 'aoo-after')
    control_before, cs = screen('aoo', 'control-before')
    control_after, ce = screen('aoo', 'control-after')
    if hands(before)[0] != 'long sword' or hands(after)[0] != 'short bow' or end <= start:
        raise Unmeasured('Exchange did not complete sword -> bow across a turn interval')
    if ce <= cs or "'In the Air':orcish knife +1" not in control_after:
        raise Unmeasured('positive control did not withdraw the fixed pack item')
    name = before.splitlines()[1].split('|')[-1].strip()
    if not name:
        raise Unmeasured('no player name in inventory banner')
    log = root / 'aoo/logs/tripaoo.log'
    if not log.is_file():
        raise Unmeasured('no AoO probe log; positive control not established')
    pattern = rf'^turn (\d+): oattack actor=<goblin> victim=<{re.escape(name)}> self=0 '
    turns = [int(t) for t in re.findall(pattern, log.read_text(), re.M)]
    control = sum(cs <= t < ce for t in turns)
    if control != 1:
        raise Unmeasured(f'positive control must record one goblin AoO, got {control}')
    count = sum(start <= t < end for t in turns)
    return count == 1, f"'-' goblin AoOs={count}, expected 1; pack-withdrawal control={control} (tripaoo.log)"

def aoo_ftte():
    # AC8(e): with Faster Than The Eye (Gauntlets of Legerdemain) neither '-' nor an
    # inventory take-off provokes; the same goblin provokes once the gauntlets are off.
    names = ('aoo-before', 'aoo-after', 'takeoff-before', 'takeoff-after',
             'control-before', 'control-after')
    scr = {t: screen('aooftte', t) for t in names}
    if 'of Legerdemain' not in scr['aoo-before'][0] or 'of Legerdemain' not in scr['takeoff-before'][0]:
        raise Unmeasured('aooftte: the character is not wearing Gauntlets of Legerdemain')
    if hands(scr['aoo-before'][0])[0] != 'long sword' or hands(scr['aoo-after'][0])[0] != 'short bow':
        raise Unmeasured("aooftte: '-' did not complete sword -> bow")
    if hands(scr['takeoff-before'][0])[0] != 'short bow' or hands(scr['takeoff-after'][0])[0] != 'Empty':
        raise Unmeasured('aooftte: the inventory take-off did not remove the bow')
    if hands(scr['control-before'][0])[0] == 'Empty' or \
            hands(scr['control-after'][0])[0] != 'Empty':
        raise Unmeasured("aooftte: the control take-off did not remove a held weapon")
    name = scr['aoo-before'][0].splitlines()[1].split('|')[-1].strip()
    log = root / 'aooftte/logs/tripaoo.log'
    if not name or not log.is_file():
        raise Unmeasured('aooftte: no player name or AoO probe log')
    pattern = rf'^turn (\d+): oattack actor=<goblin> victim=<{re.escape(name)}> self=0 '
    turns = [int(t) for t in re.findall(pattern, log.read_text(), re.M)]
    def n(a, b):
        return sum(scr[a][1] <= t < scr[b][1] for t in turns)
    swap, off, control = (n('aoo-before', 'aoo-after'), n('takeoff-before', 'takeoff-after'),
                          n('control-before', 'control-after'))
    if control != 1:
        raise Unmeasured(f'aooftte control (gauntlets off) must record one goblin AoO, got {control}')
    return (swap, off) == (0, 0), \
        f"(e) with Faster Than The Eye '-' AoOs={swap}, take-off AoOs={off} (expected 0, 0); gauntlets-off control={control}"

def aoo_all():
    ok, detail = aoo()
    before, a0 = screen('aoo2', 'control-before')
    stamps = {t: screen('aoo2', t)[1] for t in ('control-before', 'control-after',
              'empty-before', 'empty-after', 'forced-before', 'forced-after',
              'takeoff-before', 'takeoff-after')}
    name = before.splitlines()[1].split('|')[-1].strip()
    log = root / 'aoo2/logs/tripaoo.log'
    if not name or not log.is_file():
        raise Unmeasured('aoo2: no player name or AoO probe log')
    pattern = rf'^turn (\d+): oattack actor=<goblin> victim=<{re.escape(name)}> self=0 '
    turns = [int(t) for t in re.findall(pattern, log.read_text(), re.M)]
    def n(a, b):
        return sum(stamps[a] <= t < stamps[b] for t in turns)
    control = n('control-before', 'control-after')
    if control != 1:
        raise Unmeasured(f'aoo2 positive control must record one goblin AoO, got {control}')
    if hands(screen('aoo2', 'empty-before')[0]) != ('Empty', 'Empty') or \
            hands(screen('aoo2', 'empty-after')[0])[0] != BOW:
        raise Unmeasured("aoo2: '-' from an empty hand did not draw the bow")
    if hands(screen('aoo2', 'forced-before')[0])[0] != BOW or \
            hands(screen('aoo2', 'forced-after')[0])[0] != DAGGER:
        raise Unmeasured('aoo2: the forced switch did not go bow -> dagger')
    if hands(screen('aoo2', 'takeoff-before')[0])[0] != DAGGER or \
            hands(screen('aoo2', 'takeoff-after')[0])[0] != 'Empty':
        raise Unmeasured('aoo2: the inventory take-off did not remove the dagger')
    empty, forced, off = (n('empty-before', 'empty-after'), n('forced-before', 'forced-after'),
                          n('takeoff-before', 'takeoff-after'))
    ftte = aoo_ftte()
    ok = ok and ftte[0]
    return ok and (empty, forced, off) == (0, 1, 1), \
        f"{ftte[1]}; {detail}; (d) '-' from empty hand AoOs={empty} (expected 0); (b) forced switch AoOs={forced} " \
        f"(expected 1); (c) inventory take-off AoOs={off} (expected 1); control={control}"

def rawdump(scenario, tag):
    rc = int((root / f'{scenario}.status').read_text())
    if rc not in (0, 3):
        raise Unmeasured(f'{scenario} session exit {rc}; see {scenario}.out')
    paths = list((root / scenario / 'logs/screens').glob(f'*-{tag}.txt'))
    if len(paths) != 1:
        raise Unmeasured(f'missing or ambiguous {tag} dump')
    return paths[0].read_text(errors='replace')

def menu_rows(text):
    return [m.strip() for m in re.findall(r'\[[a-z]\] (.+?)(?=\s{2,}|\s*\||\s*$)', text, re.M)]

def menu():
    none = rawdump('menunone', 'menu-open')
    nrows = menu_rows(none)
    if 'Tactical Options' not in none or 'Movement' not in nrows:
        raise Unmeasured('menunone: the C menu did not open (no Tactical Options / Movement row)')
    present = rawdump('menu', 'menu-open')
    prows = menu_rows(present)
    if 'Movement' not in prows or 'short bow' not in present.splitlines()[1]:
        raise Unmeasured('menu: the C menu did not open with R (short bow) held')
    sub = menu_rows(rawdump('menu', 'submenu'))
    a = 'Switch Weapon Sets' not in nrows
    b = 'Switch Weapon Sets' in prows and sub == ['Reach set', 'Melee set', 'Short set']
    # AC7(c): grappled, the forced choice wields the reach set that '-' refuses.
    grab = mapscreen('forced', 'grapple-target')[0]
    if 'you grab' not in grab.splitlines()[1]:
        raise Unmeasured('forced: the grapple did not start')
    line = mapscreen('forced', 'forced-message')[0].splitlines()[1].split('|')[0].strip()
    after = hands(screen('forced', 'forced-after')[0])[0]
    c = line.startswith('You are now wielding') and after == SPEAR
    return a and b and c, (f'(a) no set: row absent={a}; (b) four sets, R held: row present, '
                           f'submenu {sub}; (c) grappled, forced reach set: "{line}", main hand {after}')

def sets(name):
    path = root / f'{name}.dump'
    if not path.is_file():
        raise Unmeasured(f'no {name}.dump; the {name} session wrote no save')
    text = path.read_text(errors='replace')
    block = re.search(r'^=== Weapon Sets ===\n((?:  .*\n)+)', text, re.M)
    if not block:
        raise Unmeasured(f'{name}.dump has no Weapon Sets section')
    return dict(line.strip().split(': ', 1) for line in block[1].splitlines())

def roundtrip():
    expected = {'M main': 'long sword', 'M off-hand': 'orcish dagger',
                'R main': 'short bow', 'ammo': '4 orcish shotputs',
                'X main': 'orcish longspear', 'X off-hand': '(none)',
                'S main': 'orcish knife +1', 'S off-hand': 'orcish kite shield +1'}
    for scenario in ('configure', 'reload'):
        rc = int((root / f'{scenario}.status').read_text()) if (root / f'{scenario}.status').is_file() else -1
        if rc not in (0, 3):
            raise Unmeasured(f'{scenario} session exit {rc}; see {scenario}.out')
    got = [sets('configure'), sets('reload')]
    return got[0] == expected and got[1] == expected, f'configured {got[0]}; reloaded {got[1]}'

assess(1, cycle)
assess(2, adjacent)
assess(3, flail)
assess(4, distant)
assess(5, unseen)
assess(6, grapple)
assess(11, bare)
assess(12, crowded)
assess(13, crowdfree)
assess(14, loadout_free)
assess(15, loadout_adj)
assess(10, roundtrip)
assess(8, aoo_all)
assess(7, menu)
assess(9, old)
for ac, (state, detail) in sorted(results.items()):
    print(f'{LABEL.get(ac, "AC%d" % ac)} {state}: {detail}')
print(f'Specimens: {root}')
sys.exit(1 if any(s == 'FAIL' for s, _ in results.values()) else
         2 if any(s == 'UNMEASURED' for s, _ in results.values()) else 0)
PY
