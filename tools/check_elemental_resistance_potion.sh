#!/bin/bash
# gate: live
# inc-gzkn: the potion of elemental resistance (four RESIST statuses, magnitude
# 10, one shared duration roll, equipment protected, fixed 50 gp).
#
#   tools/check_elemental_resistance_potion.sh   exit 0 every point holds, 1 a
#                                                point fails or nothing could
#                                                be measured
#
# BUILD FIRST: BACKEND=posix ./build_macos.sh. The run is one seeded session
# from a frozen character (tools/keys/elemental-resistance.keys);
# src/ElementalResistanceProbe.cpp runs on load under
# INCURSION_ELEM_RESIST_PROBE. Damage goes through the real EV_DAMAGE on the
# drinker and on a carried item. The statuses come from a real EV_DRINK.
#
# Points: 1 damage to the drinker, mean of 400 hits of 1d6 and of 6d6 per type,
# before and after; 2 carried items (scroll to fire, potion to cold, sword to
# acid and to electricity): harmed before, untouched after, and
# GearResistLevel 0 before and 10 after; 3 duration: four statuses of
# magnitude 10 from the potion's own effect, one shared roll in 10..40 units
# over 300 drinks, present one unit before the end and gone at the end;
# 4 price: 50 gp in Roark's stock at low and high Diplomacy and 50 for
# getShopCost(NULL,NULL), against a control potion whose price moves.
# A missing line fails the check.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo "FAIL: build with BACKEND=posix ./build_macos.sh"; exit 1; }
mkdir -p logs/runs
run=$(mktemp -d "$PWD/logs/runs/elemental-resistance.XXXXXX")
echo "Specimens: $run"
export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav
export INCURSION_RUN_DIR="$run"
export INCURSION_ELEM_RESIST_PROBE=1
if ! tools/headless.sh tools/keys/elemental-resistance.keys 1 >"$run/harness.txt" 2>&1; then
    cat "$run/harness.txt"
    echo 'FAIL: harness could not measure'
    exit 1
fi
python3 -I - "$run" <<'PY'
import pathlib, re, sys
logs = list(pathlib.Path(sys.argv[1]).rglob('errors.log'))
if len(logs) != 1:
    sys.exit('FAIL: missing or ambiguous errors.log')
text = logs[0].read_text(errors='replace')
for line in text.splitlines():
    if 'ELEM_RESIST' in line:
        print(line.split('  ', 1)[-1])
if 'ELEM_RESIST INCONCLUSIVE' in text or 'ELEM_RESIST done' not in text:
    sys.exit('FAIL: probe could not measure or did not finish')
bad = []
def need(ok, msg):
    if not ok:
        bad.append(msg)
T = ('fire', 'cold', 'acid', 'elec')

# 1. damage to the drinker
D = {}
for m in re.finditer(r'ELEM_RESIST dmg phase=(\w+) type=(\w+) mean1d6=(\d+) mean6d6=(\d+)', text):
    k = (m[1], m[2])
    need(k not in D, 'duplicate damage row %s' % (k,))
    D[k] = (int(m[3]) / 100.0, int(m[4]) / 100.0)
for t in T:
    b, a = D.get(('before', t)), D.get(('after', t))
    need(b is not None and a is not None, 'missing damage rows for %s' % t)
    if b and a:
        d1, d6 = b[0] - a[0], b[1] - a[1]
        need(3.0 <= b[0] <= 4.0 and 19.0 <= b[1] <= 23.0, '%s: unresisted means off the dice (%r)' % (t, b))
        need(d1 >= 0.3, '%s 1d6: mean fell only %.2f (before %.2f after %.2f)' % (t, d1, b[0], a[0]))
        need(d6 >= 3.0, '%s 6d6: mean fell only %.2f (before %.2f after %.2f)' % (t, d6, b[1], a[1]))
        print('%s: 1d6 %.2f -> %.2f (-%.2f), 6d6 %.2f -> %.2f (-%.2f)' % (t, b[0], a[0], d1, b[1], a[1], d6))

# 2. carried items and the gear grant
G = {}
for m in re.finditer(r'ELEM_RESIST gear phase=(\w+) fire=(-?\d+) cold=(-?\d+) acid=(-?\d+) elec=(-?\d+)', text):
    G[m[1]] = tuple(int(m[i]) for i in range(2, 6))
need(G.get('before') == (0, 0, 0, 0), 'GearResistLevel before is not 0 for all four: %r' % (G.get('before'),))
need(G.get('after') == (10, 10, 10, 10), 'GearResistLevel after is not 10 for all four: %r' % (G.get('after'),))
I = {}
for m in re.finditer(r'ELEM_RESIST items phase=(\w+) fire=(\d) cold=(\d) acid=(\d) elec=(\d) hard=(-?\d+),(-?\d+),(-?\d+),(-?\d+)', text):
    I[m[1]] = (tuple(int(m[i]) for i in range(2, 6)), tuple(int(m[i]) for i in range(6, 10)))
need(set(I) == {'before', 'after'}, 'missing item rows')
if set(I) == {'before', 'after'}:
    need(I['before'][0] == (1, 1, 1, 1), 'unprotected items were not all harmed: %r' % (I['before'],))
    need(I['after'][0] == (0, 0, 0, 0), 'protected items were harmed: %r' % (I['after'],))
    need(all(h >= 0 for h in I['before'][1]), 'an item is immune by material (oracle blind): %r' % (I['before'],))
    print('items harmed before %r after %r (hardness %r)' % (I['before'][0], I['after'][0], I['before'][1]))

# 3. statuses and duration
s = re.findall(r'ELEM_RESIST stati n=(\d+) types=(\d+),(\d+),(\d+),(\d+):(.*)', text)
need(len(s) == 1, 'missing stati line')
if s:
    n = int(s[0][0]); types = sorted(int(x) for x in s[0][1:5])
    rows = re.findall(r'\[(\d+),(\d+),(-?\d+),(\d)\]', s[0][5])
    need(n == 4 and len(rows) == 4, 'want 4 RESIST statuses, got %d' % n)
    need(sorted(int(r[0]) for r in rows) == types, 'statuses are not the four damage types: %r' % (rows,))
    need(all(r[1] == '10' for r in rows), 'magnitude is not 10: %r' % (rows,))
    need(all(r[3] == '1' for r in rows), 'eID is not the potion effect: %r' % (rows,))
    need(len(set(r[2] for r in rows)) == 1, 'durations differ on one drink: %r' % (rows,))
r = re.findall(r'ELEM_RESIST rolls drinks=(\d+) lo=(-?\d+) hi=(-?\d+) unequal=(\d+)', text)
need(len(r) == 1, 'missing rolls line')
if r:
    k, lo, hi, un = map(int, r[0])
    need(k == 300 and un == 0, 'rolls: %d drinks, %d with unequal durations' % (k, un))
    need(10 <= lo <= 22 and 29 <= hi <= 40, 'rolls span %d..%d, want within 10..40 and wide (20d4 is 50 rounds, sd 5)' % (lo, hi))
    print('rolls over %d drinks: %d..%d units' % (k, lo, hi))
u = re.findall(r'ELEM_RESIST duration roll=(\d+) present_stati_at_last_minus1=(-?\d+) stati_at_last=(-?\d+) dead=(\d)', text)
need(len(u) == 1 and 10 <= int(u[0][0]) <= 40 and u[0][1:] == ('4', '0', '0'),
     'duration: want 4 statuses one unit before the end, 0 at the end: %r' % (u,))

# 4. price
p = re.findall(r'ELEM_RESIST price stock=(\d+) seller=(\d) dip_low=(-?\d+) dip_high=(-?\d+) er_low=(\d+) er_high=(\d+) ctl_low=(\d+) ctl_high=(\d+) nullnull=(\d+)', text)
need(len(p) == 1, 'missing price line')
if p:
    s_, sel, dl, dh, el, eh, cl, ch, nn = map(int, p[0])
    need(s_ > 0 and sel == 1, 'Roark stock empty or not a seller')
    need(dl <= 0 and dh >= 20, 'Diplomacy levels not low and high: %d %d' % (dl, dh))
    need(cl != ch, 'control potion price does not move with Diplomacy (%d, %d): oracle blind' % (cl, ch))
    need(el == 50 and eh == 50 and nn == 50, 'price not 50 gp: low=%d high=%d null=%d' % (el, eh, nn))
if bad:
    for m in bad:
        print('FAIL: ' + m)
    sys.exit(1)
print('PASS: elemental resistance points 1-4 hold')
PY
