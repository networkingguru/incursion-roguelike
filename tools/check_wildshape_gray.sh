#!/bin/bash
# gate: live
# inc-5v47: a gray Wild Shape choice must return safely without changing form.
# Usage: tools/check_wildshape_gray.sh
# Specimens: logs/wildshape-gray/run-<timestamp>-<pid>/ and its .out file.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
mkdir -p logs/wildshape-gray
run="logs/wildshape-gray/run-$(date +%Y%m%d-%H%M%S)-$$"
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav \
INCURSION_RUN_DIR="$run" tools/headless.sh tools/keys/wildshape-gray.keys 1 > "$run.out" 2>&1
status=$?
echo "headless exit: $status; specimens: $run (report: $run.out)"
if [ "$status" -ne 0 ]; then
  echo "FAIL: headless did not exit cleanly"
  exit 1
fi
python3 - "$run/logs/screens" <<'PY'
import pathlib
import re
import sys

screens = pathlib.Path(sys.argv[1])
def read(label):
    paths = list(screens.glob('*-' + label + '.txt'))
    if len(paths) != 1:
        raise ValueError('missing or ambiguous ' + label + ' dump')
    text = paths[0].read_text()
    if not text.strip():
        raise ValueError('empty ' + label + ' dump')
    return text

try:
    menu = read('gray-menu')
    if 'Wild Shape Into What Type of Creature?' not in menu or not re.search(r'\bgiant badger\b', menu, re.I):
        raise ValueError('Giant badger Wild Shape menu not established')
    before = read('druid3')
    post = read('post-pick')
    final = read('after-action')
    for text in (post, final):
        if 'wildshape into' in text.lower():
            raise ValueError('character changed form')
        if not re.search(r'^HP:\d+/\d+', text, re.M):
            raise ValueError('post-choice gameplay screen not established')
    def turn(text):
        return int(re.search(r' turn (\d+) ===', text).group(1))
    if turn(final) <= turn(post):
        raise ValueError('final action did not advance game time')
    hp = lambda text: re.search(r'^HP:\d+/\d+', text, re.M).group(0)
    if hp(before) != hp(post):
        raise ValueError('HP changed on refused choice')
    print(f'PASS: Giant badger refused; no wildshape into message; {hp(post)}; turn {turn(post)} -> {turn(final)}')
except (OSError, ValueError, AttributeError) as error:
    print('FAIL:', error)
    sys.exit(1)
PY
