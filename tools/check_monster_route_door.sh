#!/usr/bin/env bash
# gate: live
# inc-zm6li: a monster that can open doors must route through a closed door
# that is not locked or secret, break a locked door (any door, without hands)
# only as a last resort, and never route through a secret or trapped door.
# Same RouteProbe U corridor as check_monster_route_to_target.sh, with one door
# on the bottom of the U at (12,14). Each scenario is a separate seeded session.
# fact: key bindings and overview entry -- options-2026-08-22.dat and monster-route-door.keys
# fact: player identity and initial world -- fixture kobold-rogue-seed1.sav
# fact: monster identity, position and no ambient creatures -- RouteProbe staging
# fact: staged pursuer survival -- RouteProbe sets and replenishes 10000 HP
# fact: player position and survival -- RouteProbe staging (10,10; 10000 HP)
# fact: known floor, size-compatible region and U corridor -- RouteProbe U corridor staging
# fact: the door, its flags and its trap -- RouteProbe door staging, logged on the "door" line
# fact: no line of fire and straight step blocked -- RouteProbe U corridor staging
# fact: mutual hostility and perception through wall -- RouteProbe TargetEnemy entries, CA_TELEPATHY=30
# fact: route option enabled -- RouteProbe sets OPT_MON_DJIKSTRA=1 (2 for door-pet)
# fact: hands or no hands -- kobold has hands, giant rat has M_NOHANDS, logged as nohands=
# fact: nonblocking message display -- RouteProbe sets OPT_AUTOMORE=1
# fact: route result before AI decisions -- RouteProbe calls SmartDirTo once at staging
# fact: monster AI choice, one staged pursuer -- INCURSION_FORCE_PURSUE=1
# fact: break outcome for door-bashcap -- the door is a vault door, Break DC 35 (src/Feature.cpp DoorBreakDC), above any kick roll
# fact: bypass squares for the -alt scenarios -- RouteProbe alt staging, logged as bypass= on the "door" line
# fact: reclosed door and monster returned to far side -- RouteProbe reclose staging, logged on reclose line
# fact: skill roll of the lock pick -- INCURSION_RUNTO_SKILL_ROLL=20 (door-pick) or 1 (door-pick-fail), set below per scenario
# fact: monster has Lockpicking or Knock -- RouteProbe staging: SKILL_BONUS Lockpicking, INNATE_SPELL Knock, or a wand or scroll of Knock plus mana 50
# fact: wand charges and scroll count -- RouteProbe staging, logged as kwand= and kscroll= on every observe line
# fact: turn budget -- monster-route-door.keys, 40 one-turn rests, each followed by an overview sample
# Usage: tools/check_monster_route_door.sh [scenario|all] [seed]
#   scenarios: door door-reclose door-locked door-locked-alt door-nohands door-nohands-alt
#              door-secret door-trap door-bashcap door-pet door-pick door-pick-fail
#              door-knock-spell door-knock-wand door-knock-scroll
#   door-missing stages no door and MUST report UNMEASURED (exit 2).
# Exit: 0 all PASS, 1 any FAIL, 2 any UNMEASURED and no FAIL.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
which=${1:-all}
seed=${2:-3}
if [ "$which" = all ]; then
    set -- door door-reclose door-locked door-locked-alt door-nohands door-nohands-alt \
        door-secret door-trap door-bashcap door-pet door-pick door-pick-fail \
        door-knock-spell door-knock-wand door-knock-scroll
else
    set -- "$which"
fi
mkdir -p logs/runs
worst=0
for sc in "$@"; do
    run=$(mktemp -d "$PWD/logs/runs/monster-route-door.XXXXXX") || exit 2
    roll=0
    [ "$sc" = door-pick ] && roll=20
    [ "$sc" = door-pick-fail ] && roll=1
    INCURSION_RUNTO_SKILL_ROLL=$roll INCURSION_FORCE_PURSUE=1 INCURSION_ROUTE_PROBE="$sc" INCURSION_RUN_DIR="$run" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/kobold-rogue-seed1.sav \
        tools/headless.sh tools/keys/monster-route-door.keys "$seed" > "$run/harness.txt" 2>&1
    rc=$?
    python3 - "$run" "$rc" "$sc" <<'PY'
import pathlib, sys
run = pathlib.Path(sys.argv[1]); sc = sys.argv[3]
def unmeasured(reason):
    print(f'{sc}: UNMEASURED: {reason}; specimens={run}'); sys.exit(2)
if sys.argv[2] != '0': unmeasured('headless exit ' + sys.argv[2])
log = run / 'logs/routeprobe.log'
if not log.exists(): unmeasured('no setup log')
raw = log.read_text().splitlines()
def kv(line): return dict(x.split('=', 1) for x in line.split()[1:])
doors = [kv(x) for x in raw if x.startswith('door ')]
setups = [x for x in raw if x.startswith('setup ')]
if len(setups) != 1 or len(doors) != 1: unmeasured('expected exactly one setup and one door line')
print(f'{sc}: {setups[0]}'); print(f'{sc}: door {" ".join(f"{k}={v}" for k, v in doors[0].items())}')
d = doors[0]; f = kv(setups[0])
if f.get('missing') != '0': unmeasured('no staged monster')
want_flags = {'door-locked': 8, 'door-locked-alt': 8, 'door-bashcap': 8, 'door-secret': 32,
              'door-pick': 8, 'door-pick-fail': 8, 'door-knock-spell': 8,
              'door-knock-wand': 8, 'door-knock-scroll': 8}.get(sc, 0)
want_alt = 3 if sc.endswith('-alt') else 0
want_vault = 1 if sc == 'door-bashcap' else 0
want_trap = 1 if sc == 'door-trap' else 0
want_hands = 1 if sc.startswith('door-nohands') else 0
want_pet = 1 if sc == 'door-pet' else 0
if (d['exists'], d['at']) != ('1', '12,14'): unmeasured('the staging produced no door at 12,14')
if (int(d['flags']) & ~1, int(d['solid']), int(d['trap']), int(d['nohands']), int(d['pet']),
        int(d['bypass']), int(d['vault'])) != (want_flags, 1, want_trap, want_hands, want_pet, want_alt, want_vault):
    unmeasured('door flags, solid, trap, hands or companion differ from the scenario')
if (f['mon'], f['player']) != ('14,10', '10,10') or f['blocked'] != '1' or int(f['lof']):
    unmeasured('positions, straight step or line of fire')
if not want_pet and (not int(f['perceives']) or f['hostile'] != '1' or f['telepathy'] != '30'):
    unmeasured('hostility or perception')
if want_pet and f['hostile'] != '0': unmeasured('companion is hostile')
if f['opt'] != ('2' if want_pet else '1'): unmeasured('route option')
direction, center, straight, expected = (int(f[k]) for k in ('dir', 'center', 'straight', 'expected'))
obs = [kv(x) for x in raw if x.startswith('observe ')]
gone = [o for o in obs if o.get('gone') == '1']
live = [o for o in obs if o.get('gone') != '1']
ok = True; why = []
if sc == 'door-reclose':
    resets = [kv(x) for x in raw if x.startswith('reclose ')]
    if len(resets) != 1 or int(resets[0]['opens']) < 1: unmeasured('first open/cross/reclose did not stage')
    if gone or len(live) < 40: unmeasured('missing watched creature or samples')
    after = [o for o in live if o['reclosed'] == '1']
    ok = any(int(o['opens']) >= 2 and o['dooropen'] == '1' and int(o['dist']) <= 1 for o in after)
    why = [f"reopened={int(any(int(o['opens']) >= 2 for o in after))}", f"last={after[-1]}"]
    for line in raw:
        if line.startswith(('reclose ', 'observe ')): print(sc + ': ' + line)
elif sc in ('door', 'door-pet'):
    if gone: unmeasured('the watched creature died or vanished')
    if len(live) < 40: unmeasured(f'only {len(live)} of 41 samples')
    idx = [int(o['idx']) for o in live]
    reached = any(i >= 6 for i in idx)          # door square is index 6 on the U
    opened = live[-1]['dooropen'] == '1'
    last = live[-1]; ldist = int(last['dist'])
    if sc == 'door':
        nearer = idx[-1] > 6                    # past the door, nearer the player
        first = direction == expected and direction not in (center, straight)
        ok = first and reached and opened and nearer
        why = [f'first_step={"ok" if first else "bad"}(dir={direction},expected={expected})',
               f'reached_door={int(reached)}', f'door_open_after={int(opened)}',
               f'ends_past_door={int(nearer)}(idx={idx[-1]})']
    else:
        near = ldist <= 2
        ok = reached and opened and near
        why = [f'reached_door={int(reached)}', f'door_open_after={int(opened)}',
               f'ends_within_2_of_player={int(near)}(dist={ldist})']
    # Stuck at the start for the whole budget is a FAIL; a creature that got to the
    # door approach (index 4 or more) and had not crossed when the budget ended is UNMEASURED.
    if not ok and not reached and max(idx) >= 4:
        unmeasured('turn budget ended while the creature was still walking: ' + ' '.join(why))
elif sc in ('door-locked', 'door-nohands', 'door-locked-alt', 'door-nohands-alt', 'door-bashcap'):
    if gone: unmeasured('the watched creature died or vanished')
    if len(live) < 40: unmeasured(f'only {len(live)} of 41 samples')
    last = live[-1]; opens = int(last['opens']); bashes = int(last['bashes'])
    idx = [int(o['idx']) for o in live]
    first = direction == expected and direction not in (center, straight)
    mag2 = max(int(o['mag2']) for o in live)
    if sc in ('door-locked', 'door-nohands'):
        # The only way is through the door: it walks to it and tries to break it.
        ok = first and bashes >= 1 and (opens == 0 or sc == 'door-locked')
        why = [f'first_step={"ok" if first else "bad"}(dir={direction},expected={expected})',
               f'bashes={bashes}', f'opens={opens}', f'max_idx={max(idx)}']
        if not ok and bashes == 0 and max(idx) < 5:
            unmeasured('turn budget ended before the creature reached the door: ' + ' '.join(why))
    elif sc.endswith('-alt'):
        # A longer open way exists: it takes it and never touches the door.
        near = int(last['dist']) <= 2
        ok = bashes == 0 and opens == 0 and near
        why = [f'bashes={bashes}', f'opens={opens}', f'ends_within_2_of_player={int(near)}(dist={last["dist"]})']
        if not ok and bashes == 0 and opens == 0 and not near:
            unmeasured('turn budget ended while the creature was still walking: ' + ' '.join(why))
    else:
        # The door cannot be broken: five tries, then the door is a wall.
        fin = [kv(x) for x in raw if x.startswith('final ')]
        if len(fin) != 1: unmeasured('no final route sample')
        tail = [int(o['bashes']) for o in live[-10:]]
        stopped = len(set(tail)) == 1
        refused = int(fin[0]['dir']) == int(fin[0]['center'])
        ok = bashes == 5 and mag2 == 5 and stopped and refused
        why = [f'bashes={bashes}(want 5)', f'max_door_TRIED2={mag2}(want 5)',
               f'no_bash_in_last_10_samples={int(stopped)}', f'route_refuses_door={int(refused)}']
        if not ok and bashes < 5 and max(idx) < 5:
            unmeasured('turn budget ended before the creature reached the door: ' + ' '.join(why))
    for line in raw:
        if line.startswith('final '): print(sc + ': ' + line)
elif sc in ('door-pick', 'door-pick-fail', 'door-knock-spell', 'door-knock-wand', 'door-knock-scroll'):
    if gone: unmeasured('the watched creature died or vanished')
    if len(live) < 40: unmeasured(f'only {len(live)} of 41 samples')
    last = live[-1]; first = live[0]
    picks, knocks, bashes = int(last['picks']), int(last['knocks']), int(last['bashes'])
    opened = last['dooropen'] == '1'; near = int(last['dist']) <= 2
    if sc in ('door-pick', 'door-pick-fail'):
        if sc == 'door-pick':
            # one successful pick, no break attempt, no Knock, then it reaches the player
            ok = picks >= 1 and knocks == 0 and bashes == 0 and opened and near
        else:
            # exactly five failed picks, no break before the fifth, then the break
            early = any(int(o['bashes']) > 0 and int(o['picks']) < 5 for o in live)
            ok = picks == 5 and int(last['mag3']) == 5 and knocks == 0 and bashes >= 1 and not early
            why = [f'break_before_fifth_pick={int(early)}']
        if not ok and picks == 0 and max(int(o['idx']) for o in live) < 5:
            unmeasured('turn budget ended before the creature reached the door')
        why = [f'picks={picks}', f'knocks={knocks}', f'bashes={bashes}',
               f'door_open_after={int(opened)}', f'ends_within_2_of_player={int(near)}'] + why
    else:
        extra = []
        ok = knocks == 1 and picks == 0 and bashes == 0 and opened and near
        if sc == 'door-knock-wand':
            ok = ok and int(first['kwand']) == 3 and int(last['kwand']) == 2
            extra = [f"wand_charges={first['kwand']}->{last['kwand']}(want 3->2)"]
        if sc == 'door-knock-scroll':
            ok = ok and int(first['kscroll']) == 1 and int(last['kscroll']) == 0
            extra = [f"scrolls={first['kscroll']}->{last['kscroll']}(want 1->0)"]
        if not ok and knocks == 0 and max(int(o['idx']) for o in live) < 5:
            unmeasured('turn budget ended before the creature reached the door')
        why = [f'picks={picks}', f'knocks={knocks}(want 1)', f'bashes={bashes}',
               f'door_open_after={int(opened)}', f'ends_within_2_of_player={int(near)}'] + extra
else:
    ok = direction == center
    why = [f'dir={direction}', f'CENTER={center}']
print(f'{sc}: {"PASS" if ok else "FAIL"}: ' + ' '.join(why) + f'; specimens={run}')
sys.exit(0 if ok else 1)
PY
    r=$?
    if [ "$r" = 1 ]; then worst=1; elif [ "$r" != 0 ] && [ "$worst" = 0 ]; then worst=2; fi
done
exit $worst
