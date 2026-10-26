#!/bin/bash
# gate: live
# Owner ruling 2026-10-26, bead inc-qt2c: all 18 armor qualities and WQ_DEFENDING offend only at GetPlus() == 0; negative plus is allowed.
# fact: character/map -- loaded orc-mage-seed4-gate.sav, options-2026-08-22.dat
# fact: depth/luck/category -- probe passes depths 1-10, luck 10, selected DungeonItems rows
# fact: random item qualities/plus -- random-output invariant exception in docs/VERIFICATION.md;
#       probe seeds 1,17,101,2026; no exact random counts or names asserted
# fact: plus-scaled membership -- independent AQ/WQ list in QualityPlusProbe.cpp, no effect flags
# fact: path exercised -- generated any-quality and positive-plus-scaled control counts
# fact: completion/text -- fixed probe markers; item names are diagnostics only
# Exit 0: invariant holds; 1: offending item or failed control; 2: cannot measure.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo 'QUALITY_PLUS INCONCLUSIVE build with BACKEND=posix ./build_macos.sh'; exit 2; }
mkdir -p logs/runs
run=$(mktemp -d "$PWD/logs/runs/quality-plus.XXXXXX") || exit 2
echo "Specimens: $run"
if ! INCURSION_RUN_DIR="$run" INCURSION_QUALITY_PLUS_PROBE=1 \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav \
    tools/headless.sh tools/keys/roark-stock.keys 1 >"$run/harness.txt" 2>&1; then
    cat "$run/harness.txt"
    echo 'QUALITY_PLUS INCONCLUSIVE harness failed'
    exit 2
fi
python3 -I - "$run" <<'PY'
import pathlib, re, sys
logs = list(pathlib.Path(sys.argv[1]).rglob('errors.log'))
def inconclusive(why):
    print('QUALITY_PLUS INCONCLUSIVE ' + why)
    sys.exit(2)
if len(logs) != 1:
    inconclusive('missing or ambiguous errors.log')
text = logs[0].read_text(errors='replace')
for line in text.splitlines():
    if 'QUALITY_PLUS' in line:
        print(line[line.index('QUALITY_PLUS'):])
if 'QUALITY_PLUS INCONCLUSIVE' in text or text.count('QUALITY_PLUS done') != 1:
    inconclusive('probe did not complete')
rows = re.findall(r'QUALITY_PLUS summary category=(\w+) items=(\d+) any=(\d+) scaled=(\d+) zero=(\d+) negative=(\d+)', text)
controls = re.findall(r'QUALITY_PLUS control positive_scaled=(\d+) any=(\d+)', text)
if len(rows) != 3 or {r[0] for r in rows} != {'armor', 'shield', 'weapon'} or len(controls) != 1:
    inconclusive('missing or duplicate summary/control')
counts = [tuple(map(int, r[1:])) for r in rows]
positive, any_quality = map(int, controls[0])
if any(n <= 0 or not 0 <= bad <= bad + negative <= scaled <= any_ <= n or negative < 0
       for n, any_, scaled, bad, negative in counts):
    inconclusive('invalid counts or empty category')
if any_quality != sum(c[1] for c in counts) or positive != sum(c[2]-c[3]-c[4] for c in counts):
    inconclusive('control counts disagree with summaries')
bad = sum(c[3] for c in counts)
if bad or positive == 0 or any_quality == 0:
    print(f'FAIL: zero={bad} positive_scaled={positive} any={any_quality}')
    sys.exit(1)
print('PASS: generated plus-scaled qualities have GetPlus() != 0')
PY
