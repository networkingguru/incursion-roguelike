#!/bin/bash
# gate: live
# inc-s1m5 diagnostic: current code is expected to FAIL case c. No fixes.
# Optional a|b|c|d runs one case; a is the positive control.
# a/b: independently constructed potions; b uses a fresh counterpart for
# manual EV_PICKUP because the walk already consumed the first floor item.
# c: a constructed potion carried by a kobold, dropped by real lethal damage.
# d: unmodified starting gear and a separate generated dungeon-floor potion
# from the frozen orc rogue fixture (its .keys records provenance).
# The probe relocates each scene and walks via EV_MOVE, then AutoPickupFloor.
# Manual EV_PICKUP uses ACTING/AutoLoot solely to suppress InventoryManager;
# SL_INAIR and belt Quantity are read directly. This does not test key binding.
# Full fields/stati and actual message history are in each belt-potion.log.
set -uo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
case "${1:-all}" in a|b|c|d|all) ;; *) echo "Usage: $0 [a|b|c|d]"; exit 2;; esac
cases="${1:-a b c d}"
[ "$cases" != all ] || cases="a b c d"
base="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-belt-potion"
mkdir -p "$base"
failed=0
for c in $cases; do
    run="$base/$c"
    INCURSION_BELT_POTION_PROBE="$c" INCURSION_RUN_DIR="$run" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav \
        tools/headless.sh tools/keys/belt-potion-stack.keys 1 > "$base/$c-harness.log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "FAIL case=$c harness_exit=$rc (see $base/$c-harness.log)"
        failed=1
    fi
    python3 - "$run/logs/belt-potion.log" <<'PY' || failed=1
import pathlib, sys
p = pathlib.Path(sys.argv[1])
if not p.exists():
    sys.exit(f"FAIL: missing probe log {p}")
lines = p.read_text(errors='replace').splitlines()
print('\n'.join(lines))
print(f"Specimen: {p}")
def fields(line):
    return dict(s.split('=',1) for s in line.split() if '=' in s)
auto = [fields(s) for s in lines if s.startswith('AUTO ')]
manual = [fields(s) for s in lines if s.startswith('MANUAL ')]
ok = ('COMPLETE' in lines and len(auto) == 1 and auto[0]['moved'] == '1'
      and int(auto[0]['messages']) >= 1 and auto[0]['after'] == auto[0]['expected']
      and auto[0]['inair'] == '0')
case = lines[0].split()[-1]
guards = [fields(s) for s in lines if s.startswith('GUARDS ')]
ok &= len(guards) == 1 and all(guards[0][k] == '0' for k in
                              ('threatened','raging','nohands','dropped'))
if case == 'b' or (case == 'c' and auto and auto[0]['after'] != auto[0]['expected']):
    ok &= len(manual) == 1
if case == 'c':
    kills = [fields(s) for s in lines if s.startswith('KILL ')]
    ok &= (len(kills) == 1 and kills[0]['dead'] == kills[0]['claim'] == '1'
           and kills[0]['floor_on_map'] == '1'
           and kills[0]['claimant'] == kills[0]['player'])
for row in manual:
    ok &= row['after'] == row['expected'] and row['inair'] == '0'
for stage in ('before','manual','inair'):
    items = {fields(s)['role']:fields(s) for s in lines
             if s.startswith(f'ITEM stage={stage} ')}
    if len(items) != 2: continue
    for key in ('Type','iID','eID','Plus','cHP','IFlags','Flavor','GenNum','Known','Quantity'):
        a,b = items['belt'][key], items['floor'][key]
        if a != b: print(f'DIFF stage={stage} field={key} belt={a} floor={b}')
    stati = {role: [s.split(f'role={role} ',1)[1] for s in lines
                    if s.startswith(f'STAT stage={stage} role={role} ')]
             for role in ('belt','floor')}
    if stati['belt'] != stati['floor']:
        print(f"DIFF stage={stage} stati belt={stati['belt']} floor={stati['floor']}")
    if f'COUNTERFACTUAL stage={stage} without_claim_equal=1' in lines:
        print(f'REFUSAL stage={stage}: LOOT_CLAIM belt=absent floor=present; '
              'removing only that status from a detached copy makes operator== pass')
print(('PASS' if ok else 'FAIL') + ': belt pickup expectation')
sys.exit(0 if ok else 1)
PY
done
exit "$failed"
