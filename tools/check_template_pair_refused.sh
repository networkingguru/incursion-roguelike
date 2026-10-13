#!/bin/bash
# gate: live
# inc-pp9w: the encounter chooser (Map::enTemplateOk) must not accept a second
# template that Creature::CanAddTemplate then refuses at build time.
# Probe: src/TemplatePairProbe.cpp (INCURSION_TEMPLATE_PAIR_PROBE).
# Build: BACKEND=posix ./build_macos.sh
# Run: tools/check_template_pair_refused.sh
# Exit 0 only when the chooser refuses the pair or the built monster keeps both
# templates; a refused-yet-chosen pair or missing evidence exits 1.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs/runs
RUN_DIR="$(mktemp -d "$ROOT/logs/runs/template-pair.XXXXXX")"
echo "Specimens: $RUN_DIR"
status=0
INCURSION_BIN="$ROOT/incursion-headless" \
INCURSION_TEMPLATE_PAIR_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav \
    tools/headless.sh tools/keys/template-alignment.keys 1 \
    > "$RUN_DIR/harness.txt" 2>&1 || status=$?
log="$RUN_DIR/logs/template-pair.log"
if [ ! -s "$log" ]; then
    echo "FAIL: missing probe log (harness exit $status)."
    exit 1
fi
cat "$log"
if [ "$status" -ne 0 ]; then
    echo "FAIL: harness exit $status; see $RUN_DIR/harness.txt"
    exit 1
fi
python3 - "$log" <<'PY'
from pathlib import Path
import re, sys
lines = Path(sys.argv[1]).read_text().splitlines()
if len(lines) != 2 or lines[1] != 'DONE':
    sys.exit('FAIL: incomplete probe evidence: %r' % lines)
m = re.fullmatch(r'pair=\S.* chooser_first=(\d) chooser_second=(\d) built_second=(\d)', lines[0])
if not m:
    sys.exit('FAIL: unparsable probe line: %r' % lines[0])
first, second, built = map(int, m.groups())
if not first:
    sys.exit('FAIL: chooser refused the first template; pair not exercised.')
if second and not built:
    sys.exit('FAIL: chooser accepted the second template but the build refused it.')
print('PASS: chooser_second=%d built_second=%d agree.' % (second, built))
PY
