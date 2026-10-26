#!/bin/bash
# gate: live
# inc-8fl6: wrought iron must be metallic and impose the primal armor penalty.
# fact: druid class, stats and statuses -- INCURSION_LOAD druid-shoulder-metal-seed7-opt0822.sav fixture
# fact: options -- tools/fixtures/options-2026-08-22.dat
# fact: armor base and qualities -- probe Item::Create/AddQuality (Item Acquisition equivalent), verifies MAT_IRON/MAT_WROUGHT
# fact: equipment isolation -- probe removes every occupied slot before each setup and verifies only the test armor is equipped
# fact: casting attribute -- fixture plus probe CalcValues at each setup, no turns or rolls; iron penalty checked against none
# fact: output text -- literal probe labels and integer measurements, no generated text
# Builds nothing. Exit 0 PASS, 1 regression, 2 INCONCLUSIVE setup/harness.
set -uo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-wrought-metal"
mkdir -p "$base"
INCURSION_WROUGHT_METAL_PROBE=1 INCURSION_RUN_DIR="$base/run" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav \
    tools/headless.sh tools/keys/wrought-metal.keys 7 > "$base/harness.log" 2>&1
rc=$?
log="$base/run/logs/wrought-metal.log"
echo "Specimens: $base"
[ ! -f "$log" ] || cat "$log"
if [ "$rc" != 0 ] || [ ! -f "$log" ]; then
    echo "INCONCLUSIVE: harness exit $rc or missing probe log; see $base/harness.log"
    exit 2
fi
python3 - "$log" <<'PYCODE'
import pathlib, re, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
rows = {}
for line in lines:
    match = re.fullmatch(r'(iron|orcish|wrought|none) Material=(-?\d+) isMetallic=([01]) A_PRI=(-?\d+)', line)
    if match and match[1] not in rows:
        rows[match[1]] = tuple(map(int, match.groups()[1:]))
    elif line != 'COMPLETE':
        print('INCONCLUSIVE: unexpected or incomplete probe output')
        sys.exit(2)
if len(lines) != 5 or lines[-1] != 'COMPLETE' or len(rows) != 4:
    print('INCONCLUSIVE: expected four setups and COMPLETE')
    sys.exit(2)
iron, orcish, wrought, none = (rows[k] for k in ('iron', 'orcish', 'wrought', 'none'))
if iron[1] != 1 or iron[2] >= none[2]:
    print('INCONCLUSIVE: iron control has no metallic primal penalty')
    sys.exit(2)
ok = all(row[1] == 1 and row[2] == iron[2] for row in (orcish, wrought))
print(('PASS' if ok else 'FAIL') + ': wrought and orcish armor must match the iron primal penalty')
sys.exit(0 if ok else 1)
PYCODE
