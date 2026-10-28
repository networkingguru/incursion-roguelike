#!/bin/bash
# gate: live
# inc-7s7n: the cursed cloaks Frostbite (cold damage x150/100) and Fireburn
# (fire damage x125/100) must change the damage their wearer takes.
#
#   tools/check_cloak_damage_live.sh   exit 0 every point holds, 1 a point
#                                      fails or nothing could be measured
#
# fact: character, options, slots -- fixture orc-mage-seed4-gate.sav, options-2026-08-22.dat; probe empties the cloak slot
# fact: damage amount -- probe throws a fixed 20 through the real EV_DAMAGE; no dice
# fact: attacker and resistances -- probe summons a kobold and removes RESIST stati; baseline must equal 20
# fact: cloaks -- probe builds "cloak" with the real effect and wears it by EV_WIELD; stati line proves the grant
#
# BUILD FIRST: BACKEND=posix ./build_macos.sh. src/CloakDamageProbe.cpp runs on
# load under INCURSION_CLOAK_DMG_PROBE. A missing line, INCONCLUSIVE, or a
# missing TRAP_EVENT setup line fails the check.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo "FAIL: build with BACKEND=posix ./build_macos.sh"; exit 1; }
mkdir -p logs/runs
run=$(mktemp -d "$PWD/logs/runs/cloak-damage.XXXXXX")
echo "Specimens: $run"
export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav
export INCURSION_RUN_DIR="$run"
export INCURSION_CLOAK_DMG_PROBE=1
if ! tools/headless.sh tools/keys/cloak-damage.keys 1 >"$run/harness.txt" 2>&1; then
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
    if 'CLOAK_DMG' in line:
        print(line.split('  ', 1)[-1])
if 'CLOAK_DMG INCONCLUSIVE' in text or 'CLOAK_DMG done' not in text:
    sys.exit('FAIL: probe could not measure or did not finish')
bad = []
def need(ok, msg):
    if not ok:
        bad.append(msg)
D = {}
for m in re.finditer(r'CLOAK_DMG dmg phase=(\w+) hit=(\d+) cold=(-?\d+) fire=(-?\d+)', text):
    need(m[1] not in D, 'duplicate damage row %s' % m[1])
    D[m[1]] = (int(m[2]), int(m[3]), int(m[4]))
S = {}
for m in re.finditer(r'CLOAK_DMG setup phase=(\w+) worn=(\d) trap_stati=(\d+) victim_damage_stati=(\d+)', text):
    S[m[1]] = (int(m[2]), int(m[3]), int(m[4]))
for ph in ('none', 'frostbite', 'fireburn'):
    need(ph in D, 'missing damage row for %s' % ph)
for ph in ('frostbite', 'fireburn'):
    need(ph in S, 'missing setup row for %s' % ph)
    if ph in S:
        need(S[ph][0] == 1 and S[ph][2] >= 1,
             '%s setup: worn=%d victim_damage_stati=%d (cloak not worn or stati not granted)' % (ph, S[ph][0], S[ph][2]))
if not bad:
    h, c0, f0 = D['none']
    need(h == 20 and c0 == 20 and f0 == 20, 'baseline is not 20/20/20: %r' % (D['none'],))
    fc, ff = D['frostbite'][1:]
    bc, bf = D['fireburn'][1:]
    need(fc == c0 * 150 // 100, 'Frostbite: cold %d, want %d (baseline cold %d x150/100)' % (fc, c0 * 150 // 100, c0))
    need(ff == f0, 'Frostbite: fire %d, want baseline %d' % (ff, f0))
    need(bf == f0 * 125 // 100, 'Fireburn: fire %d, want %d (baseline fire %d x125/100)' % (bf, f0 * 125 // 100, f0))
    need(bc == c0, 'Fireburn: cold %d, want baseline %d' % (bc, c0))
if bad:
    for m in bad:
        print('FAIL: ' + m)
    sys.exit(1)
print('PASS: Frostbite and Fireburn change damage as their descriptions say')
PY
