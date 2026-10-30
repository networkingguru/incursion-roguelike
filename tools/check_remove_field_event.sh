#!/bin/bash
# gate: live
# inc-5lval: Thing::Remove must not read the map after a field event has taken
# the Thing off it. Seed 22 crashed when Rainstorm's leave-effect killed a
# creature mid-sweep and Creature::Death re-entered Remove.
# fact: character -- fixture xsummon-priest-seed5-opt0822 (INCURSION_LOAD)
# fact: settings -- options-2026-08-22.dat (INCURSION_OPTIONS)
# fact: map -- the probe clears it and lays a floor patch at 5..25, so the loaded dungeon is not read
# fact: creature -- one kobold per scene, placed by the probe at (10,10); no dice
# fact: fields -- two FI_OBVIOUS fields with no resource, made by the probe
# fact: field handler -- stood in for by the probe, which Removes the kobold after the first throw
# Build: BACKEND=posix ./build_macos.sh
# Run: tools/check_remove_field_event.sh
# Expected values, and why:
#   control: no handler. Remove returns, the kobold is off the map, and
#            Creature::FieldOff is reached twice (one per field at the square).
#   handler: the kobold is removed after the first throw. That nested Remove
#            throws for both fields, then the outer Remove stops. It returns,
#            the kobold is off the map, and FieldOff is reached three times.
# Exit 0 pass; 1 defect (the handler scene began and never returned, or wrong
# numbers); 2 UNMEASURED.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs/runs
RUN_DIR="$(mktemp -d "$ROOT/logs/runs/remove-field-event.XXXXXX")"
echo "Specimens: $RUN_DIR"
status=0
INCURSION_BIN="$ROOT/incursion-headless" \
INCURSION_REMOVE_PROBE=scene INCURSION_RUN_DIR="$RUN_DIR" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav \
    tools/headless.sh tools/keys/template-alignment.keys 1 \
    > "$RUN_DIR/harness.txt" 2>&1 || status=$?
log="$RUN_DIR/logs/remove-probe.log"
if [ ! -s "$log" ]; then
    echo "UNMEASURED: missing probe log (harness exit $status)."
    exit 2
fi
cat "$log"
if grep -q '^INCONCLUSIVE' "$log"; then
    echo "UNMEASURED: the probe could not build its scene."
    exit 2
fi
if ! grep -q '^scene=control returned=1' "$log"; then
    echo "UNMEASURED: control scene did not return (harness exit $status)."
    exit 2
fi
if grep -q '^scene=handler begin' "$log" && ! grep -q '^scene=handler returned=1' "$log"; then
    echo "FAIL: Thing::Remove never returned from the handler scene (harness exit $status)."
    exit 1
fi
python3 - "$log" <<'PY'
from pathlib import Path
import re, sys
lines = Path(sys.argv[1]).read_text().splitlines()
if not lines or lines[-1] != 'DONE':
    print('UNMEASURED: probe did not reach DONE.'); sys.exit(2)
def scene(name):
    for l in lines:
        m = re.match(r'scene=%s returned=1 (.*)$' % name, l)
        if m:
            return dict(kv.split('=') for kv in m.group(1).split())
    print('UNMEASURED: no %s scene line.' % name); sys.exit(2)
want = {'control': '2', 'handler': '3'}
bad = []
for name in ('control', 'handler'):
    s = scene(name)
    if s['offmap'] != '1':
        bad.append('%s: thing still on the map' % name)
    if s['delivered'] != want[name]:
        bad.append('%s: FieldOff reached %s times, want %s' % (name, s['delivered'], want[name]))
if bad:
    print('FAIL: ' + '; '.join(bad)); sys.exit(1)
print('PASS: control delivered 2 EV_FIELDOFF; handler scene returned, thing off the map, 3 delivered.')
PY
