#!/bin/bash
# gate: live
# inc-n0ie, inc-j35aw: template alignment eligibility across eight
# monster/template cases, plus a static scan of every Template in lib/*.irh.
# fact: character -- fixture xsummon-priest-seed5-opt0822 (INCURSION_LOAD)
# fact: settings -- options-2026-08-22.dat (INCURSION_OPTIONS)
# fact: monsters and templates -- built by the probe from fixed resource names, no dice
# fact: static arm -- reads lib/*.irh text only, no game run
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
python3 - "$log" <<'PY' || status=1
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    # inc-j35aw: owner ruling -- paladin now clears Evil/Chaotic, so a sahuagin
    # takes it and ends Lawful Good (was accepted=0 under inc-n0ie).
    'case=sahuagin+paladin;template accepted=1 evil=0 good=1 lawful=1 chaotic=0',
    'case=kobold+zombie accepted=1 evil=0 good=0 lawful=0 chaotic=0',
    'case=dwarf+vampire accepted=1 evil=1 good=0 lawful=0 chaotic=1',
    'case=dwarf+paladin;template accepted=1 evil=0 good=1 lawful=1 chaotic=0',
    'case=sahuagin+blackguard;template accepted=1 evil=1 good=0 lawful=0 chaotic=1',
    'case=elf+twilight huntsman;temp accepted=1 evil=1 good=0 lawful=0 chaotic=1',
    'case=dwarf+shadowdancer;template accepted=1 evil=1 good=0 lawful=0 chaotic=1',
    'case=elf+paladin;template accepted=1 evil=0 good=1 lawful=1 chaotic=0',
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
print('PASS: all eight template alignment cases as specified.')
PY
python3 - <<'PY' || status=1
# static arm (inc-j35aw): no template may add an alignment flag without
# removing the opposite one.
import glob, re, sys
opp = {'M_GOOD': 'M_EVIL', 'M_EVIL': 'M_GOOD',
       'M_LAWFUL': 'M_CHAOTIC', 'M_CHAOTIC': 'M_LAWFUL'}
n = 0
bad = []
for path in sorted(glob.glob('lib/*.irh')):
    text = open(path, encoding='latin-1').read()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    parts = re.split(r'^([A-Z][A-Za-z]*)\s+"([^"]+)"', text, flags=re.M)
    for kind, name, body in zip(parts[1::3], parts[2::3], parts[3::3]):
        if kind != 'Template':
            continue
        n += 1
        flags = ','.join(re.findall(r'Flags:([^;]*);', body))
        toks = [t.strip() for t in flags.split(',')]
        added = {t for t in toks if t in opp}
        removed = {t[1:] for t in toks if t[:1] in '!~'}
        for a in sorted(added):
            if opp[a] not in removed:
                bad.append('%s: %s adds %s without removing %s' % (path, name, a, opp[a]))
if n == 0:
    sys.exit('FAIL: static arm parsed zero templates.')
if bad:
    print('\n'.join(bad))
    sys.exit('FAIL: static arm: %d offender(s) among %d templates.' % (len(bad), n))
print('PASS: static arm: %d templates, no unpaired alignment flag.' % n)
PY
exit "$status"
