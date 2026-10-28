#!/bin/bash
# gate: live
# gate-serial: replaces fixed scratch dirs logs/inc-klenx-module and logs/inc-klenx-run
# inc-klenx: Thing::Move writes a stale mount's coordinates after field dismount.
# fact: Medium rider, attributes and kit -- human-paladin-seed4-opt0822 save fixture
# fact: empty scenario area -- wizard Genocide Everything
# fact: Large mount and static +1 size field -- wizard Monster Summoning of scratch fixtures
# fact: mount accepts rider -- wizard Make Player Master of Monster; fixture CR 0 and M_MOUNTABLE
# fact: actors stay put -- wizard Freeze Monsters (no AI choice is read)
# fact: step and dismount squares are walkable -- wizard Change terrain type, Loose-Packed Earth
# fact: only rider grows, without a roll -- scratch field ADJUST_CIRC A_SIZ +1, EF_LIM_MTYPE MA_HUMAN, no save
# fact: mounting/dismount text and audited mount name -- fixed fixture name and engine messages
#
# Exit 0 only for observed step/dismount and clean audit; 1 for corruption or
# unreadable/unconfirmed gameplay; 2 for setup failure. Builds only a scratch
# module; requires BACKEND=posix ./build_macos.sh beforehand. SEED selects RNG.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
OPTIONS=tools/fixtures/options-2026-08-22.dat
CHARACTER=tools/fixtures/chars/human-paladin-seed4-opt0822.sav
FIXTURE=tools/fixtures/inc-klenx-growth.irh
KEYS=tools/keys/inc-klenx-growth.keys
MODULE="$ROOT/logs/inc-klenx-module"
RUN="$ROOT/logs/inc-klenx-run"
SEED="${SEED:-1}"
[ -x ./incursion-headless ] || { echo 'SETUP: run BACKEND=posix ./build_macos.sh'; exit 2; }
for f in "$OPTIONS" "$CHARACTER" "$FIXTURE" "$KEYS"; do
    [ -r "$f" ] || { echo "SETUP: missing $f"; exit 2; }
done
rm -rf "$MODULE" "$RUN" || exit 2
mkdir -p "$MODULE/mod" "$MODULE/save" "$MODULE/logs" "$RUN" || exit 2
cp -Rf lib "$MODULE/lib" || exit 2
ln -sfn "$ROOT/inc" "$MODULE/inc" || exit 2
cat "$FIXTURE" >> "$MODULE/lib/main.irc" || exit 2
INCURSIONPATH="$MODULE/" ./incursion-headless -compile main.irc < /dev/null > "$MODULE/compile.log" 2>&1
if [ ! -s "$MODULE/mod/Incursion.Mod" ]; then
    tail -20 "$MODULE/compile.log"
    echo 'SETUP: scratch module did not compile'; exit 2
fi
INCURSION_RUN_DIR="$MODULE" INCURSION_OPTIONS="$OPTIONS" \
    INCURSION_LOAD="$CHARACTER" INCURSION_MAP_AUDIT=1 \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN/harness.txt" 2>&1 < /dev/null
status=$?
python3 - "$MODULE" "$status" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1]) / 'logs'
def fail(message):
    print('INCONCLUSIVE: ' + message)
    sys.exit(1)
try:
    audit = (root / 'mapaudit.log').read_text()
except (OSError, UnicodeError):
    fail('cannot read logs/mapaudit.log')
findings = [line.strip() for line in audit.splitlines()
            if ('Thing linked at a square it does not claim' in line or
                'Thing not in the Contents chain of its own square' in line)
            and 'klenx test mount/' in line]
def screen(tag):
    files = list((root / 'screens').glob('*' + tag + '*'))
    if not files:
        fail('missing ' + tag + ' screen')
    return '\n'.join(p.read_text(errors='replace') for p in files)
if 'You mount the' not in screen('mounted'):
    fail('mounting was not confirmed')
before = screen('before-step')
after = screen('after-step')
if 'Mounted' not in before:
    fail('rider was not mounted immediately before the step')
if 'You are thrown from your mount' in before:
    fail('dismount happened before the step')
if 'You are thrown from your mount' not in after or 'You grow one size category' not in after:
    fail('field-triggered dismount during the step was not confirmed')
if findings:
    print('RED: stale mount coordinates after field-triggered dismount')
    for line in dict.fromkeys(findings):
        print(line)
    sys.exit(1)
if sys.argv[2] != '0':
    fail('headless exit ' + sys.argv[2])
if not audit.strip() or re.search(r'-- [1-9][0-9]* kind\(s\)', audit):
    fail('audit is empty or contains other corruption')
print('GREEN: mounted step triggered dismount; map audit clean')
PY
