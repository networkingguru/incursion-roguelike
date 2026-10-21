#!/bin/bash
# gate: live
# inc-1qyv: the True Blows potion (status IGNORES_WEAPON_IMMUNITY, 7200 units).
#
#   tools/check_true_blows.sh      exit 0 every point holds, 1 a point fails or
#                                  nothing could be measured
#
# BUILD FIRST: BACKEND=posix ./build_macos.sh. The run is one seeded session
# from a frozen character (tools/keys/true-blows.keys); src/TrueBlowsProbe.cpp
# runs on load under INCURSION_TRUE_BLOWS_PROBE. Every attack goes through the
# real Creature::Strike, so it meets the incorporeal pass-through gate
# (src/Fight.cpp:6250), the 50% ignore gate (:7990) and the weapon-immunity
# gate (:8146). The status comes from a real EV_DRINK.
#
# Points: 1 weapon immunity (levels 1 and 2, sword and bare hands);
# 2 incorporeal (+0 sword passes through before, hits after with about half
# ignored by the 50% gate, +1 control matches the after); 3 to-hit and damage
# unchanged; 4 duration (present at 7199 DoTurn calls, gone at 7200);
# 5 price (50 gp in Roark's stock at low and high Diplomacy, and 50 for
# getShopCost(NULL,NULL)). A missing line fails the check.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo "FAIL: build with BACKEND=posix ./build_macos.sh"; exit 1; }
mkdir -p logs/runs
run=$(mktemp -d "$PWD/logs/runs/true-blows.XXXXXX")
echo "Specimens: $run"
export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav
export INCURSION_RUN_DIR="$run"
export INCURSION_TRUE_BLOWS_PROBE=1
if ! tools/headless.sh tools/keys/true-blows.keys 1 >"$run/harness.txt" 2>&1; then
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
    if 'TRUE_BLOWS' in line:
        print(line.split('  ', 1)[-1])
bad = []
def need(ok, msg):
    if not ok:
        bad.append(msg)
if 'TRUE_BLOWS INCONCLUSIVE' in text or 'TRUE_BLOWS done' not in text:
    sys.exit('FAIL: probe could not measure or did not finish')

M = {}
for m in re.finditer(r'TRUE_BLOWS m scene=(\w+) phase=([\w-]+) plus=(-?\d+) status=(\d) trials=(\d+) damaged=(\d+) ignored=(\d+) wimmune=(\d+) none=(\d+)', text):
    k = (m[1], m[2])
    need(k not in M, 'duplicate measurement %s' % (k,))
    M[k] = dict(plus=int(m[3]), status=int(m[4]), n=int(m[5]), dam=int(m[6]),
                ign=int(m[7]), wim=int(m[8]), none=int(m[9]))
def row(scene, phase):
    r = M.get((scene, phase))
    need(r is not None, 'missing measurement %s/%s' % (scene, phase))
    return r or dict(plus=-9, status=-9, n=1, dam=0, ign=0, wim=0, none=1)

wil = dict(re.findall(r'TRUE_BLOWS scene=(\w+) wil=(\d+)', text))
need(wil.get('wimm1') == '1' and wil.get('wimm2') == '2' and wil.get('incor') == '0',
     'scene immunity levels wrong: %r' % wil)
need(re.search(r'scene=incor wil=0 plane=3', text) is not None, 'incorporeal victim is not on the ethereal plane')

# 2. incorporeal, through Strike
b, c, a = row('incor', 'before'), row('incor', 'control'), row('incor', 'after')
need(b['status'] == 0 and a['status'] == 1 and c['status'] == 0, 'incor status flags wrong')
need(b['plus'] == 0 and a['plus'] == 0 and c['plus'] == 1, 'incor weapon pluses wrong')
need(b['dam'] + b['ign'] == 0 and b['none'] == b['n'],
     'incor before: +0 sword reached the monster (%r)' % b)
for name, r in (('control', c), ('after', a)):
    hit = r['dam'] + r['ign']
    need(hit >= 40, 'incor %s: only %d of %d attacks reached the monster' % (name, hit, r['n']))
    frac = r['ign'] / hit if hit else -1
    need(0.25 <= frac <= 0.75, 'incor %s: %.0f%% of landed hits ignored, want 25-75%%' % (name, 100 * frac))
    print('incor %s: reached=%d ignored=%d (%.0f%%)' % (name, hit, r['ign'], 100 * frac))

# 1. weapon immunity
for scene in ('wimm1', 'wimm2'):
    b, c, a = row(scene, 'before'), row(scene, 'control'), row(scene, 'after')
    bb, ba = row(scene, 'before-bare'), row(scene, 'after-bare')
    need(b['dam'] == 0 and b['wim'] >= 170, '%s before: +0 sword was not stopped (%r)' % (scene, b))
    need(c['dam'] >= 170 and c['wim'] == 0, '%s control: +%d sword did not harm (%r)' % (scene, c['plus'], c))
    need(a['dam'] >= 170 and a['wim'] == 0, '%s after: +0 sword did not harm (%r)' % (scene, a))
    need(bb['dam'] == 0 and bb['wim'] >= 170, '%s before: bare hands were not stopped (%r)' % (scene, bb))
    need(ba['dam'] >= 170 and ba['wim'] == 0, '%s after: bare hands did not harm (%r)' % (scene, ba))
    print('%s: damaged before=%d after=%d bare before=%d after=%d' % (scene, b['dam'], a['dam'], bb['dam'], ba['dam']))
need(row('wimm2', 'control')['plus'] == 2, 'level-2 control is not a +2 weapon')

# 3. bonuses
bon = dict((p, (h, d)) for p, h, d in re.findall(r'TRUE_BLOWS bonus phase=(\w+) hit=(-?\d+) dmg=(\S+)', text))
need(set(bon) == {'before', 'after'}, 'missing bonus lines')
need(bon.get('before') == bon.get('after'), 'to-hit/damage changed: %r' % bon)
print('bonuses before/after:', bon)

# 4. duration
d = re.findall(r'TRUE_BLOWS drink return=(-?\d+) status=(\d+) duration=(-?\d+)', text)
need(len(d) == 1 and d[0][1:] == ('1', '7200'), 'drinking did not grant 7200-unit status: %r' % d)
u = re.findall(r'TRUE_BLOWS duration at7199=(\d) at7200=(\d) dead=(\d)', text)
need(u == [('1', '0', '0')], 'duration: want present at 7199, gone at 7200, alive: %r' % u)

# 5. price
p = re.findall(r'TRUE_BLOWS price stock=(\d+) seller=(\d) dip_low=(-?\d+) dip_high=(-?\d+) tb_low=(\d+) tb_high=(\d+) ctl_low=(\d+) ctl_high=(\d+) nullnull=(\d+)', text)
need(len(p) == 1, 'missing price line')
if p:
    s, sel, dl, dh, tl, th, cl, ch, nn = map(int, p[0])
    need(s > 0 and sel == 1, 'Roark stock empty or not a seller')
    need(dl <= 0 and dh >= 20, 'Diplomacy levels not low and high: %d %d' % (dl, dh))
    need(cl != ch, 'control potion price does not move with Diplomacy (%d, %d): oracle blind' % (cl, ch))
    need(tl == 50 and th == 50 and nn == 50, 'True Blows price not 50 gp: low=%d high=%d null=%d' % (tl, th, nn))
if bad:
    for m in bad:
        print('FAIL: ' + m)
    sys.exit(1)
print('PASS: True Blows points 1-5 hold')
PY
