#!/bin/bash
# gate: live
# inc-2rws: the potion of water walking (status WATER_WALKING, (20d4+1)/2 units).
#
#   tools/check_water_walking_potion.sh   exit 0 every point holds, 1 a point
#                                         fails or nothing could be measured
#
# BUILD FIRST: BACKEND=posix ./build_macos.sh. The run is one seeded session
# from a frozen character (tools/keys/water-walking-potion.keys);
# src/WaterWalkingProbe.cpp runs on load under INCURSION_WATER_WALKING_PROBE.
# Each trial throws EV_MOVE at the real "deep water" or "turbulent water"
# handler (lib/dungeon.irh): the Swim check, "fail to make progress" abort and
# drowning damage live there. The status comes from a real EV_DRINK.
#
# Points: 1 before drinking, the Swim path runs (character with 1 Swim rank:
# many trials fail or drown, each terrain); 2 after drinking, all 200 trials
# per terrain pass with no failure and no drowning damage; 3 rolled duration
# falls in 10..40 units over 400 drinks, mean about 25 (20d4 is 50 +- 5
# rounds, so the spread is narrow); 4 the
# status is present at the last unit minus one and gone at the last unit, for
# three rolls; 5 price 50 gp in Roark's stock at low and high Diplomacy and 50
# for getShopCost(NULL,NULL), against a control potion whose price moves.
# A missing line fails the check.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo "FAIL: build with BACKEND=posix ./build_macos.sh"; exit 1; }
mkdir -p logs/runs
run=$(mktemp -d "$PWD/logs/runs/water-walking.XXXXXX")
echo "Specimens: $run"
export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav
export INCURSION_RUN_DIR="$run"
export INCURSION_WATER_WALKING_PROBE=1
if ! tools/headless.sh tools/keys/water-walking-potion.keys 1 >"$run/harness.txt" 2>&1; then
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
    if 'WATER_WALKING' in line:
        print(line.split('  ', 1)[-1])
if 'WATER_WALKING INCONCLUSIVE' in text or 'WATER_WALKING done' not in text:
    sys.exit('FAIL: probe could not measure or did not finish')
bad = []
def need(ok, msg):
    if not ok:
        bad.append(msg)

M = {}
for m in re.finditer(r'WATER_WALKING m phase=(\w+) terrain=(\w+) status=(\d) swim=(-?\d+) trials=(\d+) passed=(\d+) failed=(\d+) drowned=(\d+)', text):
    k = (m[1], m[2])
    need(k not in M, 'duplicate measurement %s' % (k,))
    M[k] = dict(status=int(m[3]), swim=int(m[4]), n=int(m[5]), ok=int(m[6]),
                fail=int(m[7]), drown=int(m[8]))
for ph in ('before', 'after'):
    for t in ('deep', 'turbulent'):
        r = M.get((ph, t))
        need(r is not None, 'missing measurement %s/%s' % (ph, t))
        if r is None:
            continue
        need(r['n'] == 200 and r['ok'] + r['fail'] + r['drown'] == r['n'], 'trial counts wrong %s' % (r,))
        need(r['status'] == (1 if ph == 'after' else 0), '%s/%s: status flag wrong' % (ph, t))
        need(r['swim'] <= 2, '%s/%s: character is not unskilled in Swim (%d)' % (ph, t, r['swim']))
        if ph == 'before':
            need(r['fail'] + r['drown'] >= 20, 'before %s: Swim path barely ran (%r)' % (t, r))
            need(r['drown'] >= 1, 'before %s: no drowning seen (%r)' % (t, r))
        else:
            need(r['ok'] == r['n'] and r['fail'] == 0 and r['drown'] == 0, 'after %s: Swim path still ran (%r)' % (t, r))
        print('%s %s: passed=%d failed=%d drowned=%d (swim=%d)' % (ph, t, r['ok'], r['fail'], r['drown'], r['swim']))

d = re.findall(r'WATER_WALKING drink return=(-?\d+) status=(\d+) duration=(-?\d+)', text)
need(len(d) == 1 and d[0][1] == '1' and 10 <= int(d[0][2]) <= 40, 'drinking did not grant the status in 10..40: %r' % d)
r = re.findall(r'WATER_WALKING range drinks=(\d+) min=(-?\d+) max=(\d+) mean10=(\d+) inrange=(\d+)', text)
need(len(r) == 1, 'missing range line')
if r:
    n, lo, hi, mean10, inr = map(int, r[0])
    need(n == 400 and inr == n, 'rolls outside 10..40: %r' % (r[0],))
    need(lo >= 10 and hi <= 40 and lo <= 22 and hi >= 28, 'rolls do not spread around 25: min=%d max=%d' % (lo, hi))
    need(240 <= mean10 <= 260, 'mean duration %.1f, want about 25' % (mean10 / 10))
t = re.findall(r'WATER_WALKING timing run=(\d) dur=(\d+) atdurm1=(-?\d) atdur=(-?\d) dead=(\d)', text)
need(len(t) == 3 and all(x[2:] == ('1', '0', '0') for x in t), 'timing: want present at dur-1, gone at dur, alive, 3 runs: %r' % t)

p = re.findall(r'WATER_WALKING price stock=(\d+) seller=(\d) dip_low=(-?\d+) dip_high=(-?\d+) ww_low=(\d+) ww_high=(\d+) ctl_low=(\d+) ctl_high=(\d+) nullnull=(\d+)', text)
need(len(p) == 1, 'missing price line')
if p:
    s, sel, dl, dh, wl, wh, cl, ch, nn = map(int, p[0])
    need(s > 0 and sel == 1, 'Roark stock empty or not a seller')
    need(dl <= 0 and dh >= 20, 'Diplomacy levels not low and high: %d %d' % (dl, dh))
    need(cl != ch, 'control potion price does not move with Diplomacy (%d, %d): oracle blind' % (cl, ch))
    need(wl == 50 and wh == 50 and nn == 50, 'Water Walking price not 50 gp: low=%d high=%d null=%d' % (wl, wh, nn))
if bad:
    for m in bad:
        print('FAIL: ' + m)
    sys.exit(1)
print('PASS: Water Walking potion points 1-5 hold')
PY
