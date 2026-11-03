#!/bin/bash
# gate: live
# inc-3nvr4: Detonate must stop when a monster victim has no mundane inventory.
# fact: loaded character/world -- INCURSION_LOAD=xsummon-priest-seed5-opt0822.sav
# fact: settings -- INCURSION_OPTIONS=options-2026-08-22.dat
# fact: caster/victim/positions -- INCURSION_DETONATE_PROBE creates two kobolds,
#       clears other map objects, lays floor, and keeps the player out of range
# fact: victim inventory -- probe creates exactly one mundane dagger (control)
#       or no inventory (null); READY verifies ownership, count and magic state
# fact: action/event fields -- probe calls ThrowEff(EV_INVOKE, Detonate rID,
#       caster, victim, NULL), as ChooseAction does; no AI choice or turns
# fact: fatigue/mana/HP -- probe sets 100 FP, 10000 mana and 10000 HP; verifies
#       Fortitude <8; result must show 98 FP, proving PRE(EV_EFFECT) ran
# fact: victim Will save -- INCURSION_FORCE_SAVE_ROLL=1 (natural one fails)
# fact: blast damage -- not asserted; 2d10 cannot kill either 10000-HP monster
# fact: item destruction -- probe reads the original item's handle/F_DELETE
# fact: NULL diagnostic/crash -- fresh per-scene log, flushed READY before cast,
#       harness exit and Detonate NULL reference diagnostic; no random text read
# Exit 0 both pass; 1 defect or inability to establish the observation.
# Build: BACKEND=posix ./build_macos.sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs/runs
OUT="$(mktemp -d "$ROOT/logs/runs/detonate-null-target.XXXXXX")"
echo "Specimens: $OUT"
failed=0
for scene in control null; do
    run="$OUT/$scene"
    mkdir -p "$run"
    status=0
    INCURSION_BIN="$ROOT/incursion-headless" \
    INCURSION_DETONATE_PROBE="$scene" INCURSION_FORCE_SAVE_ROLL=1 \
    INCURSION_RUN_DIR="$run" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav \
        tools/headless.sh tools/keys/template-alignment.keys 1 \
        > "$run/harness.txt" 2>&1 || status=$?
    python3 - "$run" "$scene" "$status" <<'PY' || failed=1
from pathlib import Path
import re
import sys
run, scene, status = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
def fail(reason):
    print(f'FAIL: {scene}: {reason} (harness exit {status})')
    sys.exit(1)
log = run / 'logs/detonate-probe.log'
if not log.is_file():
    fail('cannot establish scene: missing probe log')
lines = log.read_text().splitlines()
for line in lines:
    print(line)
ready = [line for line in lines if line.startswith(f'READY scene={scene} ')]
if len(ready) != 1 or not re.fullmatch(
        rf'READY scene={scene} ready=1 items={1 if scene == "control" else 0} '
        r'fort=-?\d+ fatigue=100 save_roll=1', ready[0]):
    fail('cannot establish controlled setup')
# Engine diagnostics can span lines. Inspect only this fresh run's text logs.
for path in run.rglob('*'):
    if path.is_file() and path.suffix in ('.log', '.txt'):
        text = path.read_text(errors='replace')
        if re.search(r'NULL object reference[^\n]*(?:\n[^\n]*){0,3}Detonate', text, re.I):
            fail('Detonate NULL object reference')
if status >= 128:
    fail('crash after controlled setup')
if status != 0:
    fail('session did not finish normally')
result = [line for line in lines if line.startswith(f'RESULT scene={scene} ')]
if len(result) != 1 or not re.fullmatch(
        rf'RESULT scene={scene} returned=1 result=-?\d+ fatigue=98 '
        rf'item_gone={1 if scene == "control" else 0}', result[0]):
    fail('missing cast result, fatigue walk not reached, or item not destroyed')
print(f'PASS: {scene}: ' + ('mundane item destroyed' if scene == 'control'
                          else 'empty inventory handled without a NULL reference'))
PY
done
exit "$failed"
