#!/bin/bash
# inc-18q6 phase 3: anchoring must allow weapon melee but still stop movement.
# Oracle: Stuck on the live status line, a new attack roll against an adjacent
# goblin, and a failed escape that spends time without changing position.
# Wrong setup exits 2; a measured violation exits 1. Prove red by restoring
# the WAttack STUCK refusal in src/Fight.cpp and rebuilding the posix binary.
# Usage: tools/check_stuck_fights.sh (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
       INCURSION_MAP_AUDIT=0 tools/headless.sh tools/keys/stuck-fights.keys 4 2>&1)"
result=$?
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if [ "$result" != 0 ] || [ ! -d "$run/logs/screens" ]; then
    echo "INCONCLUSIVE: the fixture did not finish its gameplay setup."
    echo "$out"
    exit 2
fi
python3 - "$run" <<'PY'
import pathlib
import re
import sys

run = pathlib.Path(sys.argv[1])
screens = run / 'logs/screens'

def inconclusive(message):
    print('INCONCLUSIVE: ' + message)
    print('      run: ' + str(run))
    sys.exit(2)

def screen(label):
    files = list(screens.glob('*-' + label + '.txt'))
    if len(files) != 1:
        inconclusive('missing or ambiguous ' + label + ' screen.')
    return files[0].read_text()

def status(text):
    return next((line.split('|')[0] for line in text.splitlines()
                 if line.startswith('HP:')), '')

def entangled(text):
    return bool(re.search(r'\b(?:Entangled|Ent)\b', status(text)))

def stuck(text):
    return bool(re.search(r'\b(?:Stuck|Stk)\b', status(text)))

def position(text):
    # The entrance and player share a row in this fixed, empty entry chamber.
    rows = [line.split('|')[0] for line in text.splitlines()
            if '#' in line and '@' in line and '<' in line]
    if len(rows) != 1:
        inconclusive('cannot locate the player relative to the cave entrance.')
    return rows[0].index('@') - rows[0].index('<')

def turn(text):
    return int(re.search(r'^=== screen .* turn (\d+) ===', text)[1])

anchored = screen('anchored')
before = screen('before-attack')
attacked = screen('attacked')
refused = screen('refused')
if not stuck(anchored) or "You've become stuck!" not in anchored:
    inconclusive('the fixture did not anchor the character in tanglefoot strands.')
if not stuck(before) or 'goblin' not in before.lower():
    inconclusive('the anchored character has no adjacent goblin target.')
if re.search(r'Attack: 1d20 .*\[(?:hit|miss)\]', before):
    inconclusive('an old attack roll would contaminate the melee oracle.')

failures = []
def require(condition, message):
    if not condition:
        failures.append(message)

require(stuck(attacked) and position(attacked) == position(before),
        'the melee attempt must leave the creature Stuck in its original square.')
require(bool(re.search(r'Attack: 1d20 .*\[(?:hit|miss)\]', attacked))
        and turn(attacked) > turn(before),
        'the anchored creature did not execute a melee attack and print its roll.')
require(stuck(refused) and position(refused) == position(attacked)
        and turn(refused) > turn(attacked) and 'You remain stuck fast!' in refused,
        'the same creature must fail to move and remain Stuck after its escape attempt.')
require(bool(re.search(r'Escape Artist Check:.*\[failure\]', refused))
        and bool(re.search(r'Strength Check:.*\[failure\]', refused)),
        'movement must be refused by failed escape checks, not by an unrelated obstacle.')
for message in failures:
    print('FAIL: ' + message)
if not failures:
    print('PASS: the anchored creature executed a melee attack while still Stuck.')
    print('      ' + next(line.split('|')[0].rstrip() for line in attacked.splitlines()
                          if line.startswith('Attack:')))
    print('      Movement refused: same square, still Stuck; both escape checks failed.')
print('      run: ' + str(run))
sys.exit(1 if failures else 0)
PY
