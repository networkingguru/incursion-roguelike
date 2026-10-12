#!/bin/bash
# gate: live
# inc-n0ie: template alignment eligibility across five monster/template cases.
# Build: BACKEND=posix ./build_macos.sh
# Run: tools/check_template_alignment.sh
# Exit 0 only when every case line is present and correct; defect or missing
# evidence exits 1.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs/runs
RUN_DIR="$(mktemp -d "$ROOT/logs/runs/template-alignment.XXXXXX")"
echo "Specimens: $RUN_DIR"
status=0
INCURSION_BIN="$ROOT/incursion-headless" \
INCURSION_TEMPLATE_ALIGNMENT_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav \
    tools/headless.sh tools/keys/template-alignment.keys 1 \
    > "$RUN_DIR/harness.txt" 2>&1 || status=$?
log="$RUN_DIR/logs/template-alignment.log"
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
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    'case=sahuagin+paladin;template accepted=0 evil=1 good=0 lawful=1 chaotic=0',
    'case=kobold+zombie accepted=1 evil=0 good=0 lawful=0 chaotic=0',
    'case=dwarf+vampire accepted=1 evil=1 good=0 lawful=0 chaotic=1',
    'case=dwarf+paladin;template accepted=1 evil=0 good=1 lawful=1 chaotic=0',
    'case=sahuagin+blackguard;template accepted=1 evil=1 good=0 lawful=0 chaotic=1',
]
if not lines or lines[-1] != 'DONE':
    sys.exit('FAIL: incomplete probe evidence.')
body = lines[:-1]
if body != expected:
    for i, want in enumerate(expected):
        got = body[i] if i < len(body) else '<missing>'
        if got != want:
            sys.exit('FAIL: case %d: want %r got %r' % (i + 1, want, got))
    sys.exit('FAIL: unexpected extra case lines: %r' % body[len(expected):])
print('PASS: all five template alignment cases as specified.')
PY
