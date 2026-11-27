#!/bin/bash
# gate: live
# Does the player see a square a moving torch lights? Path 2 of the reproduction: a lane, the
# player at x=10, a goblin with a lit torch walking east away from the player, who never moves.
# Red when a lane square the light map calls lit (brightness >= LIGHT_SEE_MIN, 48) at x >= 18 is
# not VI_VISIBLE, or the goblin stands on such a square and the player does not perceive it.
# Defect: inc-znk1w. A moving light source left the player's VI_VISIBLE flags frozen.
# fact: character -- fixture kobold-rogue-seed1 via INCURSION_LOAD
# fact: arena and torch carrier -- scratch-module scene tools/repro_torch_visibility.irh (PATHMODE 2)
# fact: carrier actions -- EV_MOVE east, a pure function of its square; INCURSION_RESCAN_HOLD=1
# fact: hiding -- explicit HIDING on the player in the scene, no random hide roll
# fact: options -- tools/fixtures/options-2026-08-22.dat, named by INCURSION_OPTIONS
# fact: seed -- 1, held fixed; the check asserts no random result
# fact: observation -- INCURSION_VIS_PROBE log (logs/vis.log), VI_VISIBLE and Perceives read after CalcVision
#
# Usage: tools/check_torch_visibility.sh [--no-build] [waits]   exit 0 pass, 1 fail, 2 inconclusive
# Needs the headless build: BACKEND=posix ./build_macos.sh. Specimens: the run directory it prints.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
WAITS="${1:-40}"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: ./incursion-headless not built"; exit 2; }
WORK="$ROOT/logs/torch-visibility-$$-$(date +%H%M%S)"
mkdir -p "$WORK/scene" "$WORK/run"
cp -R lib inc "$WORK/scene/"
sed 's/PATHMODE/2/g' tools/repro_torch_visibility.irh >> "$WORK/scene/lib/main.irc"
INCURSIONPATH="$WORK/scene/" ./incursion-headless -compile main.irc > "$WORK/compile.log" 2>&1 \
    || { echo "INCONCLUSIVE: scene compile failed, see $WORK/compile.log"; exit 2; }
[ -d "$WORK/scene/mod" ] || { echo "INCONCLUSIVE: no scene mod, see $WORK/compile.log"; exit 2; }
cp -R "$WORK/scene/mod" "$WORK/run/mod"
python3 - "$WAITS" "$WORK/input.keys" <<'PY'
import sys
n=int(sys.argv[1])
t=open('tools/keys/torch-visibility.keys').read().replace('# WAIT_PREFIX','.\n'*n)
open(sys.argv[2],'w').write(t)
PY
fx="$(tools/fixture_cache.sh kobold-rogue-seed1)" || { echo "INCONCLUSIVE: fixture build failed"; exit 2; }
INCURSION_RESCAN_HOLD=1 INCURSION_VIS_PROBE=1 INCURSION_RUN_DIR="$WORK/run" INCURSION_LOAD="$fx" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    tools/headless.sh "$WORK/input.keys" 1 > "$WORK/headless.out" 2>&1
log="$WORK/run/logs/vis.log"
[ -f "$log" ] || { echo "INCONCLUSIVE: no vis.log; see $WORK/headless.out"; exit 2; }
python3 - "$log" <<'PY'
import sys
blocks=[]; cur=None
for line in open(sys.argv[1]):
    f=line.split()
    if f[0]=='V': cur={'turn':int(f[1].split('=')[1]),'P':f[2].split('=')[1],'L':[],'M':[]}; blocks.append(cur)
    elif f[0]=='L': cur['L'].append(tuple(map(int,f[1:])))
    elif f[0]=='M': cur['M'].append(tuple(map(int,f[1:])))
MIN=48; bad=0; checked=0; seen_far=0; per_checks=0
for b in blocks:
    if b['P']!='10,15': continue          # the scene's lane, not the level the character arrived on
    b['M']=[m for m in b['M'] if m[1]==15]
    if not b['M']: continue
    gx=b['M'][0][0]            # the carrier is the only other creature in the scene
    for x,lvl,vis in b['L']:
        if x>=18 and lvl>=MIN and abs(x-gx)<=6:   # the torch's own pool; other level light is out of the lane
            checked+=1
            if not vis: bad+=1; print('RED turn=%d goblin at x=%d: lit square x=%d level=%d not visible'%(b['turn'],gx,x,lvl))
    for x,y,per,lit in b['M']:
        if x>=18 and lit:
            per_checks+=1
            if not per: bad+=1; print('RED turn=%d goblin at %d,%d on a lit square, per=0'%(b['turn'],x,y))
if checked==0 or per_checks==0:
    print('INCONCLUSIVE: checked %d lit squares and %d goblin samples; the scene did not run'%(checked,per_checks)); sys.exit(2)
print('%s: %d ShowMap blocks, %d lit lane squares checked, %d goblin samples, %d violations'%('FAIL' if bad else 'PASS',len(blocks),checked,per_checks,bad))
sys.exit(1 if bad else 0)
PY
st=$?
echo "run: $WORK"
exit $st
