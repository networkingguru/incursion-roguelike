#!/bin/bash
# gate: live
# inc-w6t0: does Stone to Flesh, cast at an adjacent statue through the real
# aiming keys, replace the statue with a NEW live monster of the statue's type,
# and does a failed DC 15 Fortitude save (system shock) leave the engine's own
# corpse of that type instead?
#
#   tools/check_stone_to_flesh_statue.sh     exit 0 every row holds, 1 otherwise
#
# BUILD FIRST: BACKEND=posix ./build_macos.sh. Four seeded sessions from a
# frozen character; tools/keys/stone-to-flesh-statue.keys learns the spell and
# casts it with [m], RIGHT, ENTER. src/StoneToFleshProbe.cpp puts a statue east
# of the player and logs STONE_FLESH_BEFORE / STONE_FLESH_AFTER. The save roll
# is pinned with INCURSION_FORCE_SAVE_ROLL: 20 always passes, 1 always fails.
#   typed/pass    statue of a goblin, roll 20: live goblin, statue gone, and its
#                 attitude equals a goblin built the way the level generator
#                 builds one
#   untyped/pass  statue with no type, roll 20: live monster, CR within the
#                 depth CR, not a dragon, not M_NO_CORPSE
#   typed/fail    roll 1: no creature, a goblin corpse on the square
#   untyped/fail  roll 1: no creature, a corpse whose type obeys the same rules
#   creature      a goblin that is turning to stone is the target: STONING gone,
#                 same goblin, no HP change, no statue (no save for a cure)
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo "FAIL: build with BACKEND=posix ./build_macos.sh"; exit 1; }
mkdir -p logs/runs
bad=0
row() { # name statue roll
    local name=$1 statue=$2 roll=$3
    local run; run=$(mktemp -d "$PWD/logs/runs/stone-to-flesh-statue-$name.XXXXXX")
    echo "Specimens ($name): $run"
    if ! INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
         INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav \
         INCURSION_RUN_DIR="$run" INCURSION_STONE_FLESH_PROBE=statue \
         INCURSION_STONE_FLESH_STATUE=$statue INCURSION_FORCE_SAVE_ROLL=$roll \
         tools/headless.sh tools/keys/stone-to-flesh-statue.keys 1 >"$run/harness.txt" 2>&1; then
        cat "$run/harness.txt"; echo "FAIL: $name harness could not measure"; bad=1; return
    fi
    python3 -I - "$run" "$name" "$statue" "$roll" <<'PY' || bad=1
import pathlib, re, sys
run, name, statue, roll = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
logs = list(run.rglob('errors.log'))
if len(logs) != 1: sys.exit('FAIL: %s: missing or ambiguous errors.log' % name)
text = logs[0].read_text(errors='replace')
def fields(tag):
    m = re.findall(r'STONE_FLESH_%s (.*)' % tag, text)
    if len(m) != 1 or 'INCONCLUSIVE' in text:
        sys.exit('FAIL: %s: %s line missing or inconclusive' % (name, tag))
    return dict(re.findall(r'(\w+)=(.*?)(?= \w+=|$)', m[0]))  # names may hold spaces
b, a = fields('BEFORE'), fields('AFTER')
print('%s: before statues=%s creature=%s corpses=%s' % (name, b['statues'], b['creature'], b['corpses']))
print('%s: after  statues=%s creature=%s type=%s corpses=%s corpse_type=%s cr=%s depthcr=%s dragon=%s nocorpse=%s'
      % (name, a['statues'], a['creature'], a['type'], a['corpses'], a['corpse_type'],
         a['cr'], a['depthcr'], a['dragon'], a['nocorpse']))
bad = []
if b['statues'] != '1' or b['creature'] != 'none' or b['corpses'] != '0': bad.append('bad start')
if a['statues'] != '0': bad.append('statue still there')
if statue != 'untyped' and a['type'] != statue: bad.append('type %s, want %s' % (a['type'], statue))
if a['type'] == 'none': bad.append('no creature type resulted')
if a['dragon'] != '0': bad.append('dragon')
if a['nocorpse'] != '0': bad.append('M_NO_CORPSE type')
if statue == 'untyped' and a['type'] != 'none' and int(a['cr']) > int(a['depthcr']):
    bad.append('CR %s above depth CR %s' % (a['cr'], a['depthcr']))
if roll == '20':
    if a['creature'] != 'yes' or a['alive'] != '1': bad.append('creature not alive after a passed save')
    if a['corpses'] != '0': bad.append('corpse after a passed save')
    for k in ('hostile', 'peaceful'):  # PartyID is random per build, so only printed
        if a[k] != a['ref_' + k]: bad.append('attitude %s=%s, fresh one has %s' % (k, a[k], a['ref_' + k]))
    if statue.endswith('goblin') and (a['weapons'] != '1' or a['ref_weapons'] != '1'): bad.append('weapons %s, fresh %s, want 1 and 1' % (a['weapons'], a['ref_weapons']))
    if statue == 'blue goblin' and (int(a['innate']) < 1 or int(a['ref_innate']) < 1):
        bad.append('EV_BIRTH did not run: innate spells %s, fresh %s' % (a['innate'], a['ref_innate']))
    if statue.endswith('goblin'): print('%s: gear weapons=%s (fresh %s), EV_BIRTH innate spells=%s (fresh %s)' % (name, a['weapons'], a['ref_weapons'], a['innate'], a['ref_innate']))
    print('%s: attitude hostile=%s peaceful=%s party=%s | fresh hostile=%s peaceful=%s party=%s'
          % (name, a['hostile'], a['peaceful'], a['party'], a['ref_hostile'], a['ref_peaceful'], a['ref_party']))
else:
    if a['creature'] != 'none': bad.append('creature alive after a failed save')
    if a['corpses'] != '1': bad.append('corpses=%s, want 1' % a['corpses'])
    if a['corpse_type'] != a['type'] or a['type'] == 'none': bad.append('corpse type %s' % a['corpse_type'])
    if statue != 'untyped' and a['corpse_type'] != statue: bad.append('corpse type %s, want %s' % (a['corpse_type'], statue))
if bad: sys.exit('FAIL: %s: %s' % (name, '; '.join(bad)))
PY
}
crow() { # a petrifying goblin as the target: the creature path must still cure it
    local run; run=$(mktemp -d "$PWD/logs/runs/stone-to-flesh-statue-creature.XXXXXX")
    echo "Specimens (creature): $run"
    if ! INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
         INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav \
         INCURSION_RUN_DIR="$run" INCURSION_STONE_FLESH_PROBE=statue \
         INCURSION_STONE_FLESH_STATUE=stoned-goblin \
         tools/headless.sh tools/keys/stone-to-flesh-creature.keys 1 >"$run/harness.txt" 2>&1; then
        cat "$run/harness.txt"; echo "FAIL: creature harness could not measure"; bad=1; return
    fi
    python3 -I - "$run" <<'PY' || bad=1
import pathlib, re, sys
logs = list(pathlib.Path(sys.argv[1]).rglob('errors.log'))
if len(logs) != 1: sys.exit('FAIL: creature: missing or ambiguous errors.log')
text = logs[0].read_text(errors='replace')
b = re.findall(r'STONE_FLESH_CRE_BEFORE type=(.*) stoning=(\d) hp=(-?\d+)', text)
a = re.findall(r'STONE_FLESH_CRE_AFTER same_creature=(\d) stoning=(\d) hp=(-?\d+) hp_before=(-?\d+) statues=(\d)', text)
if len(b) != 1 or len(a) != 1 or 'INCONCLUSIVE' in text: sys.exit('FAIL: creature: probe lines missing or inconclusive')
print('creature: before type=%s stoning=%s hp=%s' % b[0])
print('creature: after  same_creature=%s stoning=%s hp=%s (was %s) statues=%s' % a[0])
bad = []
if b[0][1] != '1': bad.append('not petrifying at start')
if a[0][0] != '1': bad.append('creature gone or replaced')
if a[0][1] != '0': bad.append('STONING still present')
if a[0][2] != a[0][3]: bad.append('HP changed')
if a[0][4] != '0': bad.append('a statue appeared')
if bad: sys.exit('FAIL: creature: ' + '; '.join(bad))
PY
}
crow
row typed-pass goblin 20
row birth-pass "blue goblin" 20
row untyped-pass untyped 20
row typed-fail goblin 1
row untyped-fail untyped 1
[ $bad -eq 0 ] && echo 'PASS: Stone to Flesh turns a statue into a new monster; system shock kills it' || exit 1
