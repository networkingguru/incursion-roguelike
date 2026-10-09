#!/bin/bash
# gate: live
# inc-u3dp phase 4: distraction marks, roar status, countersong and step check.
# (0 GREEN, 1 RED, 2 INCONCLUSIVE)
#
# THE ORACLE is INCURSION_HIDE_DIST_PROBE, which arms HideDistProbe
# (src/HideDistProbe.cpp) at the top of Game::Play. The probe dispatches the
# real events (EV_RATTACK, Map::MakeNoiseXY, EV_SATTACK/A_ROAR, UseAbility for
# the countersong, EV_MOVE) and prints one line per case:
#   HIDE_DIST case=<name> expect=<n> got=<n>
# plus HIDE_STEP lines from src/Move.cpp (gated by INCURSION_HIDE_DIST_PROBE).
# The probe never calls HideSetKey. Literal expectations are in the probe;
# the case set and count are hard-coded here.
#
# GREEN: every case has expect == got, the case names match, and the step
# check used mod=-5. RED: any mismatch. INCONCLUSIVE: no COMPLETE line, an
# INCONCLUSIVE line, a wrong case count, or an abnormal headless exit.
#
# Usage: tools/check_hide_distraction.sh [seed]
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo 'INCONCLUSIVE: build the posix backend'; exit 2; }
RUN="$(mktemp -d "$PWD/logs/hide-distraction-XXXXXX")"
INCURSION_HIDE_DIST_PROBE=1 INCURSION_RUN_DIR="$RUN" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav \
    tools/headless.sh tools/keys/hide-distraction.keys "${1:-1}" > "$RUN.out" 2>&1
status=$?
python3 - "$RUN" "$status" <<'PY'
import pathlib, re, sys
run = pathlib.Path(sys.argv[1])
log = run / 'logs/errors.log'
if not log.exists():
    print(f'INCONCLUSIVE: no probe log; {run}.out'); sys.exit(2)
lines = [s for s in log.read_text().splitlines()
         if not s.startswith('    ') and ('HIDE_DIST' in s or 'HIDE_STEP' in s)]
pathlib.Path(str(run) + '.lines').write_text('\n'.join(lines) + '\n')
if any('INCONCLUSIVE' in s for s in lines) or not any('HIDE_DIST COMPLETE' in s for s in lines):
    print(f'INCONCLUSIVE: incomplete scene/probe; {run}.lines'); sys.exit(2)
if int(sys.argv[2]) not in (0, 3):
    print(f'INCONCLUSIVE: headless exit {sys.argv[2]}; {run}.out'); sys.exit(2)
EXPECTED = ['attack_marks_attacker', 'attack_marks_target', 'attack_attacker_spot_mod',
    'attack_two_one_entry', 'attack_two_same_mod', 'distract_before_action',
    'distract_gone_after_action', 'noise_maker_not_marked', 'noise_listener_marked',
    'noise_listener_listen_mod', 'noise_no_spot_roll', 'noise_mark_gone_after_action',
    'roar_deaf_is_deaf', 'roar_roarer_not_marked', 'roar_listener_marked',
    'roar_listener_live', 'roar_listener_spot_mod', 'roar_listener_listen_mod',
    'roar_deaf_not_marked', 'roar_live_at_2_rounds', 'roar_gone_at_3_rounds',
    'roar_re_marked', 'countersong_clears_roar']
cases = {}; bad = []
for s in lines:
    m = re.search(r'HIDE_DIST case=(\S+) expect=(-?\d+) got=(-?\d+)', s)
    if m:
        n, e, g = m.group(1), int(m.group(2)), int(m.group(3))
        if n in cases: bad.append('duplicate case ' + n)
        cases[n] = (e, g)
        if e != g: bad.append(f'{n}: expect {e} got {g}')
if sorted(cases) != sorted(EXPECTED):
    bad.append(f'case set differs: got {sorted(set(cases) ^ set(EXPECTED))}')
# step check: between step_begin and step_end, every HIDE_STEP for the distracted listener has mod=-5
inside = False; steps = []
for s in lines:
    if 'step_begin' in s: inside = True
    elif 'step_end' in s: inside = False
    elif inside and 'HIDE_STEP' in s: steps.append(s)
if not steps: bad.append('step check: no HIDE_STEP line (listener never rolled)')
for s in steps:
    if 'mod=-5' not in s: bad.append('step check not -5: ' + s)
for n in EXPECTED: print(n, cases.get(n))
print(f'step lines: {len(steps)}')
if bad:
    print('RED: ' + '\n'.join(bad) + f'\nRun: {run}'); sys.exit(1)
print(f'GREEN: all {len(EXPECTED)} cases plus the step check. Run: {run}')
PY
