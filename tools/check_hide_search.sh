#!/bin/bash
# gate: live
# inc-u3dp phase 5: searching finds hidden creatures. 0 GREEN, 1 RED, 2 INCONCLUSIVE.
#
# THE ORACLE is INCURSION_HIDE_SEARCH_PROBE, which arms HideSearchProbe
# (src/HideSearchProbe.cpp). The probe never calls HideSearch. It finds a
# secret door through Throw(EV_SEARCH), then runs 60 real ChooseAction calls for
# a monster that lost sight of the hidden player and for a monster with no
# target. The key script then presses the real search key once against a
# hidden rat. SpotCheck logs one HIDE_TRIGGER_ROLL line per roll and
# Monster::ChooseAction logs "HIDE_SEARCH ACT watcher=<handle>" per ACT_SEARCH.
#
# Cases (hard-coded count 7):
#   door_found, player_rolls_equal_keys (1 key -> exactly 1 roll player vs
#   rat), player_search_spots (>=1 roll result=1), loss_chooses_search (>=1 ACT
#   in 60 calls), loss_search_rolls_player (every ACT of the loss monster is
#   followed by a roll loss vs player), control_never_searches (0 ACT),
#   scene_present.
# GREEN: all cases hold. RED: a case fails. INCONCLUSIVE: no COMPLETE line, an
# INCONCLUSIVE line, no scene, or an abnormal headless exit.
#
# Usage: tools/check_hide_search.sh [seed]
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo 'INCONCLUSIVE: build the posix backend'; exit 2; }
RUN="$(mktemp -d "$PWD/logs/hide-search-XXXXXX")"
INCURSION_HIDE_SEARCH_PROBE=1 INCURSION_RUN_DIR="$RUN" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav \
    tools/headless.sh tools/keys/hide-search-test.keys "${1:-1}" > "$RUN.out" 2>&1
status=$?
python3 - "$RUN" "$status" <<'PY'
import pathlib, re, sys
run = pathlib.Path(sys.argv[1])
log = run / 'logs/errors.log'
if not log.exists():
    print(f'INCONCLUSIVE: no probe log; {run}.out'); sys.exit(2)
lines = [s for s in log.read_text().splitlines()
         if not s.startswith('    ') and ('HIDE_SEARCH' in s or 'HIDE_TRIGGER_ROLL' in s)]
pathlib.Path(str(run) + '.lines').write_text('\n'.join(lines) + '\n')
if any('INCONCLUSIVE' in s for s in lines) or not any('HIDE_SEARCH COMPLETE' in s for s in lines):
    print(f'INCONCLUSIVE: incomplete scene/probe; {run}.lines'); sys.exit(2)
if int(sys.argv[2]) not in (0, 3):
    print(f'INCONCLUSIVE: headless exit {sys.argv[2]}; {run}.out'); sys.exit(2)
KEYS = 1
EXPECTED_CASES = 7
scene = [re.search(r'HIDE_SEARCH SCENE player=(\d+) hidden=(\d+) loss=(\d+) ctrl=(\d+)', s) for s in lines]
scene = [m for m in scene if m]
if len(scene) != 1:
    print(f'INCONCLUSIVE: expected one scene; {run}.lines'); sys.exit(2)
pl, hid, loss, ctrl = map(int, scene[0].groups())
if not (pl and hid and loss and ctrl):
    print(f'INCONCLUSIVE: scene has a missing creature; {run}.lines'); sys.exit(2)
si = next(i for i, s in enumerate(lines) if 'HIDE_SEARCH SCENE' in s)
ci = next(i for i, s in enumerate(lines) if 'HIDE_SEARCH COMPLETE' in s)
rollre = re.compile(r'HIDE_TRIGGER_ROLL watcher=(\d+) hider=(\d+) .* result=(\d)')
res = {}
res['scene_present'] = True
res['door_found'] = any('HIDE_SEARCH DOOR found=1' in s for s in lines)
# monster phase: lines before COMPLETE (the monsters run inside the probe)
acts = {}; follow = {}
for i, s in enumerate(lines[:ci]):
    m = re.search(r'HIDE_SEARCH ACT watcher=(\d+)', s)
    if m:
        w = int(m.group(1)); acts[w] = acts.get(w, 0) + 1
        j = i + 1; ok = False
        while j < len(lines) and 'HIDE_TRIGGER_ROLL' in lines[j]:
            r = rollre.search(lines[j])
            if r and int(r.group(1)) == w and int(r.group(2)) == pl: ok = True
            j += 1
        if ok: follow[w] = follow.get(w, 0) + 1
res['loss_chooses_search'] = acts.get(loss, 0) >= 1
res['loss_search_rolls_player'] = acts.get(loss, 0) >= 1 and follow.get(loss, 0) == acts.get(loss, 0)
res['control_never_searches'] = acts.get(ctrl, 0) == 0
# player phase: rolls after COMPLETE are from the real search key
prolls = [rollre.search(s) for s in lines[ci:]]
prolls = [(int(m.group(1)), int(m.group(2)), int(m.group(3))) for m in prolls if m]
mine = [r for r in prolls if r[0] == pl and r[1] == hid]
res['player_rolls_equal_keys'] = len(mine) == KEYS
res['player_search_spots'] = any(r[2] == 1 for r in mine)
bad = [k for k, v in res.items() if not v]
for k, v in res.items(): print(k, 'ok' if v else 'FAIL')
print(f'acts={acts} follow={follow} player_rolls={mine}')
if len(res) != EXPECTED_CASES:
    print('INCONCLUSIVE: wrong case count'); sys.exit(2)
if bad:
    print('RED: ' + ', '.join(bad) + f'\nRun: {run}'); sys.exit(1)
print(f'GREEN: all {len(res)} cases. Run: {run}')
PY
