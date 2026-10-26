#!/bin/bash
# gate: live
# gate-serial: --prove-red overwrites tracked src files and rebuilds the shared binaries
# inc-icp3: Roark's necessities stock.
#
#   tools/check_roark_stock.sh               exit 0 every point holds, 1 a point fails,
#                                            2 nothing could be measured
#   tools/check_roark_stock.sh --prove-red   exit 0 when breaking RestockShop turns it red
#
# BUILD FIRST: BACKEND=posix ./build_macos.sh. The oracle is src/RoarkStockProbe.cpp
# (INCURSION_ROARK_STOCK_PROBE=count|price|refill). Its table of necessities and tier
# sizes is its own copy of the ruling, NOT read from Roark's resource.
#
# Points: 1 count -- on seeds 1-20 every necessity holds exactly its tier size in the
# shop InitShopkeeper builds; 2 price -- each fixed-price item costs its fixed gp at
# Diplomacy 0 and 30 and by getShopCost(NULL,NULL), while control potions move;
# 3 refill -- after stock is spent, opening the store inside the same game day refills
# nothing, opening it on a later day tops every short necessity up to its tier size,
# and a necessity above its tier size is not reduced (sheaf arrow and sling stone
# included); 4 craft cost; 5 cost -- list cost of dart 5 cp, sling stone 1 cp, controls
# sheaf arrow 5 cp and crossbow bolt 10 cp (TITEM Cost, hundredths of a gp).
# inc-6i0x: count also holds six ammunition rows (sheaf arrow, flight arrow, crossbow
# bolt, hand crossbow dart, dart, sling stone) at exactly 50, mundane (plus 0, no effect).
# fact: character -- fixture orc-mage-seed4-gate.sav, options-2026-08-22.dat
# fact: shop contents -- probe sets p->storeSeed and builds InitShopkeeper; RestockShop tops to tier
# fact: game day -- probe sets theGame->Turn directly
# fact: list cost -- TITEM Cost read directly, no roll
set -uo pipefail
cd "$(dirname "$0")/.."
PROVE=0
[ "${1:-}" = "--prove-red" ] && PROVE=1

run_check() {
    [ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; return 2; }
    mkdir -p logs/runs
    local run mode
    run=$(mktemp -d "$PWD/logs/runs/roark-stock.XXXXXX")
    echo "Specimens: $run"
    export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
    export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav
    for mode in count price refill craft cost; do
        mkdir -p "$run/$mode"
        if ! INCURSION_RUN_DIR="$run/$mode" INCURSION_ROARK_STOCK_PROBE=$mode \
                tools/headless.sh tools/keys/roark-stock.keys 1 >"$run/$mode/harness.txt" 2>&1; then
            cat "$run/$mode/harness.txt"
            echo "INCONCLUSIVE: harness could not measure ($mode)"
            return 2
        fi
    done
    python3 -I - "$run" <<'PY'
import pathlib, re, sys
run = pathlib.Path(sys.argv[1])
bad = []
def need(ok, msg):
    if not ok: bad.append(msg)
def log(mode):
    f = list((run / mode).rglob('errors.log'))
    if len(f) != 1:
        print('INCONCLUSIVE: missing or ambiguous errors.log for ' + mode); sys.exit(2)
    t = f[0].read_text(errors='replace')
    stock = 'not in stock' in t
    inconclusive = [l for l in t.splitlines() if 'ROARK_STOCK INCONCLUSIVE' in l and 'not in stock' not in l]
    if inconclusive or ('ROARK_STOCK done' not in t and not stock):
        print('INCONCLUSIVE: probe could not measure ' + mode); sys.exit(2)
    need(not stock, mode + ': a fixed-price or control item is missing from Roark\'s stock')
    return t

# 1. count
t = log('count')
rows = re.findall(r'ROARK_STOCK count seed=(\d+) item=([\w ]+) have=(\d+) need=(\d+)', t)
sums = re.findall(r'ROARK_STOCK seed=(\d+) short=(\d+) over=(\d+) total=(\d+)', t)
need(len(sums) == 20 and 'ROARK_STOCK done' in t, 'count: want 20 seeds, got %d' % len(sums))
need(len(rows) == 20 * 39, 'count: want 780 rows, got %d' % len(rows))
for seed, short, over, total in sums:
    need((short, over, total) == ('0', '0', '39'), 'count seed %s: short=%s over=%s total=%s' % (seed, short, over, total))
for seed, item, have, nd in rows:
    need(have == nd, 'count seed %s %s: have %s need %s' % (seed, item, have, nd))
AMMO = ('sheaf arrow', 'flight arrow', 'crossbow bolt', 'hand crossbow dart', 'dart', 'sling stone')
got = {a: [r for r in rows if r[1] == a] for a in AMMO}
for a in AMMO:
    need(len(got[a]) == 20 and all(r[3] == '50' and r[2] == '50' for r in got[a]),
         'count ammunition %s: want 20 seeds holding exactly 50, got %r' % (a, [(r[0], r[2], r[3]) for r in got[a]]))
mun = re.findall(r'ROARK_STOCK mundane seed=(\d+) item=([\w ]+) plus=(-?\d+) eff=(\d+)', t)
for a in AMMO:
    m = [x for x in mun if x[1] == a]
    need(len(m) == 20 and all(x[2] == '0' and x[3] == '0' for x in m),
         'count ammunition %s: want 20 mundane stacks (plus 0, no effect), got %r' % (a, m))
print('count: %d seeds, %d rows, short=%d over=%d' % (len(sums), len(rows),
      sum(int(s[1]) for s in sums), sum(int(s[2]) for s in sums)))

# 2. price
t = log('price')
P = {m[0]: tuple(map(int, m[1:])) for m in re.findall(
    r'ROARK_STOCK price item=([\w ]+) kind=\w+ dip_low=(-?\d+) dip_high=(-?\d+) low=(\d+) high=(\d+) nullnull=(\d+)', t)}
FIX = {'cure disease': 200, 'antitoxin': 100, 'remove curse': 50, 'valour': 50,
       'identify scroll': 100, 'mana': 50, 'true blows': 50, 'water walking': 50,
       'elemental resistance': 50}
for k, gp in FIX.items():
    r = P.get(k)
    need(r is not None, 'price: missing ' + k)
    if r:
        need(r[2] == gp and r[3] == gp and r[4] == gp, 'price %s: want %d got low=%d high=%d null=%d' % (k, gp, r[2], r[3], r[4]))
        need(r[0] <= 0 and r[1] >= 20, 'price %s: Diplomacy not low/high (%d,%d)' % (k, r[0], r[1]))
for k in ('restoration', 'restore strength', 'dimension door', 'dispel magic scroll',
          'transmute rock to mud scroll', 'pickaxe'):
    r = P.get(k)
    need(r is not None and r[2] > r[3], 'price control %s does not fall with Diplomacy: oracle blind (%r)' % (k, r))
print('price:', ' '.join('%s=%d/%d' % (k, P[k][2], P[k][3]) for k in FIX if k in P))

# 3. refill
t = log('refill')
S = {m[0]: tuple(map(int, m[1:])) for m in re.findall(
    r'ROARK_STOCK refill phase=(\w+) ret=(-?\d+) short=(\d+) over=(\d+) antitoxin=(\d+) mana=(\d+)', t)}
I = {}
for ph, item, have, nd in re.findall(r'ROARK_STOCK refill phase=(\w+) item=([\w ]+) have=(\d+) need=(\d+)', t):
    I.setdefault(ph, {})[item] = (int(have), int(nd))
def ph(n):
    need(n in S, 'refill: missing phase ' + n); return S.get(n, (0,) * 5)
# (ret, short, over, antitoxin, mana)
need(ph('init')[1:3] == (0, 0), 'refill init: a fresh shop is not full')
need(ph('spent')[1] == 8 and ph('spent')[2] == 1, 'refill spent: setup did not short 8 / raise 1: %r' % (ph('spent'),))
need(ph('sameday')[0] == 0 and ph('sameday')[1:] == ph('spent')[1:], 'refill sameday: stock changed or refill ran: %r' % (ph('sameday'),))
need(ph('nextday')[0] == 1 and ph('nextday')[1] == 0, 'refill nextday: not topped up: %r' % (ph('nextday'),))
need(ph('nextday')[3] == 9 and ph('nextday')[2] == 1, 'refill nextday: necessity above tier size was reduced: %r' % (ph('nextday'),))
for item, (have, nd) in I.get('nextday', {}).items():
    need(have == nd or (item == 'antitoxin' and have == 9), 'refill nextday %s: have %d need %d' % (item, have, nd))
need(ph('sameday2')[0] == 0 and ph('sameday2')[1] == 1 and ph('sameday2')[4] == 2,
     'refill sameday2: a second refill ran the same day: %r' % (ph('sameday2'),))
need(ph('day8')[0] == 1 and ph('day8')[1] == 0 and ph('day8')[4] == 12, 'refill day8: %r' % (ph('day8'),))
for a in ('sheaf arrow', 'sling stone'):
    need(I.get('spent', {}).get(a, (0, 0))[0] < 50 and I.get('nextday', {}).get(a) == (50, 50),
         'refill ammunition %s: spent=%r nextday=%r, want short then 50' % (a, I.get('spent', {}).get(a), I.get('nextday', {}).get(a)))
print('refill: spent short=%d | same day ret=%d short=%d | next day ret=%d short=%d antitoxin=%d' % (
    ph('spent')[1], ph('sameday')[0], ph('sameday')[1], ph('nextday')[0], ph('nextday')[1], ph('nextday')[3]))
# 4. craft cost: a fixed-price effect uses the level table, not its ITEM_COST list
t = log('craft')
K = {m[0]: tuple(map(int, m[1:])) for m in re.findall(
    r'ROARK_STOCK craft item=([\w +]+) fixed=(\d) level=(\d+) xp=(\d+) gp=(\d+) craft_gp=(\d+)', t)}
WANT = {'mana': (16, 128), 'identify scroll': (8, 64), 'true blows': (64, 512),
        'cure disease': (64, 512), 'control girdle+2 giant strength': (80, 640)}
for k, (xp, gp) in WANT.items():
    r = K.get(k)
    need(r is not None, 'craft: missing ' + k)
    if r:
        need((r[2], r[3]) == (xp, gp), 'craft %s: want xp=%d gp=%d got xp=%d gp=%d' % (k, xp, gp, r[2], r[3]))
        need(r[0] == (0 if k.startswith('control') else 1), 'craft %s: fixed flag %d' % (k, r[0]))
print('craft:', ' '.join('%s=%d/%d' % (k, K[k][2], K[k][3]) for k in WANT if k in K))
# 5. list cost (TITEM Cost, hundredths of a gp): dart 5 cp, sling stone 1 cp; controls unchanged
t = log('cost')
C = {m[0]: int(m[1]) for m in re.findall(r'ROARK_STOCK cost item=([\w ]+) list=(\d+)', t)}
for k, v in {'dart': 5, 'sling stone': 1, 'sheaf arrow': 5, 'crossbow bolt': 10}.items():
    need(C.get(k) == v, 'cost %s: want list %d hundredths of a gp, got %r' % (k, v, C.get(k)))
print('cost:', ' '.join('%s=%s' % kv for kv in sorted(C.items())))
if bad:
    for m in bad: print('FAIL: ' + m)
    sys.exit(1)
print('PASS: Roark necessities points 1-5 hold')
PY
}

if [ "$PROVE" = 0 ]; then
    run_check; exit $?
fi

# --prove-red: break each site in turn, rebuild, expect red, restore, rebuild.
keep=$(mktemp -d -t roark-prove-red)
cp src/Social.cpp "$keep/Social.cpp"; cp src/Skills.cpp "$keep/Skills.cpp"
trap 'cp "$keep/Social.cpp" src/Social.cpp; cp "$keep/Skills.cpp" src/Skills.cpp; BACKEND=posix ./build_macos.sh >/dev/null 2>&1; echo "restored sources and rebuilt"' EXIT
prove() { # <file> <from> <to> <what>
    python3 -I - "$1" "$2" "$3" <<'PY' || { echo "INCONCLUSIVE: mutation site not found"; exit 2; }
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
assert s.count(a) == 1
open(p, 'w').write(s.replace(a, b))
PY
    BACKEND=posix ./build_macos.sh >/dev/null 2>&1 || { echo "INCONCLUSIVE: broken build did not compile"; exit 2; }
    run_check >"$keep/out.txt" 2>&1; rc=$?
    grep -E "^FAIL: (craft|refill nextday:)" "$keep/out.txt" | head -3
    cp "$keep/Social.cpp" src/Social.cpp; cp "$keep/Skills.cpp" src/Skills.cpp
    if [ "$rc" = 1 ]; then echo "PROVED RED: $4"; else echo "NOT PROVED ($4): exit $rc"; exit 1; fi
}
prove src/Social.cpp $'        if (have >= tier)\n            continue;\n' $'        continue;\n' "RestockShop skips the top-up"
prove src/Skills.cpp $'!TEFF(it->eID)->HasFlag(EF_FIXED_PRICE) &&\n\t    TEFF' $'TEFF' "CraftCosts stops testing EF_FIXED_PRICE"
exit 0
