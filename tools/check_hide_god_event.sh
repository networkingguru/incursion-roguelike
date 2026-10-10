#!/bin/bash
# gate: live
# inc-u3dp phase 6: EV_SPOT_CHECK reaches the god-watch dispatch. 0 GREEN,
# 1 RED, 2 INCONCLUSIVE.
#
# WHAT IT PROVES. SpotCheck throws EV_SPOT_CHECK (src/HideCheck.cpp). Every
# dispatched event is offered to each god twice, wrapped as GODWATCH(e.Event)
# for a character actor and GODWATCH(EVICTIM(e.Event)) for a character victim
# (src/Event.cpp:263-302). This check drives a real roll -- a hiding player with
# two visible monster watchers, through the HideTriggerProbe scene -- and reads
# the probe lines the dispatch site logs when it sees GODWATCH(EV_SPOT_CHECK) or
# GODWATCH(EVICTIM(EV_SPOT_CHECK)). SpotCheck also logs one HIDE_TRIGGER_ROLL
# line per roll, so the ratio of dispatches to rolls is exact.
#
# GREEN when the scene completed, at least one roll happened, and at least one
# god-watch dispatch was logged for every roll. RED when a roll happened with no
# dispatch. INCONCLUSIVE when the scene or the run did not complete.
#
# RED PROOF. Comment out the ThrowVal(EV_SPOT_CHECK, ...) call at
# src/HideCheck.cpp:204 and run again: rolls still log, but no dispatch does,
# so the ratio falls to zero and this is a RED. Restore the call.
#
# Usage: tools/check_hide_god_event.sh [seed]
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo 'INCONCLUSIVE: build the posix backend'; exit 2; }
RUN="$(mktemp -d "$PWD/logs/hide-god-event-XXXXXX")"
INCURSION_HIDE_GOD_PROBE=1 INCURSION_HIDE_TRIGGER_PROBE=1 INCURSION_RUN_DIR="$RUN" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav \
    tools/headless.sh tools/keys/hide-triggers.keys "${1:-1}" > "$RUN.out" 2>&1
status=$?
python3 - "$RUN" "$status" <<'PY'
import pathlib, re, sys
run = pathlib.Path(sys.argv[1])
log = run / 'logs/errors.log'
if not log.exists():
    print(f'INCONCLUSIVE: no probe log; {run}.out'); sys.exit(2)
lines = [s for s in log.read_text().splitlines()
         if not s.startswith('    ') and ('HIDE_TRIGGER' in s or 'HIDE_GOD' in s)]
pathlib.Path(str(run) + '.lines').write_text('\n'.join(lines) + '\n')
if any('INCONCLUSIVE' in s for s in lines) or not any('HIDE_TRIGGER COMPLETE' in s for s in lines):
    print(f'INCONCLUSIVE: incomplete scene/probe; {run}.lines'); sys.exit(2)
if int(sys.argv[2]) not in (0, 3):
    print(f'INCONCLUSIVE: headless exit {sys.argv[2]}; {run}.out'); sys.exit(2)

rolls = [s for s in lines if 'HIDE_TRIGGER_ROLL' in s]
god = [s for s in lines if re.search(r'HIDE_GOD dispatched ev=(\d+)', s)]
if not rolls:
    print(f'INCONCLUSIVE: no roll happened; {run}.lines'); sys.exit(2)
# Every HIDE_GOD line must name one of the two wrapped event numbers.
want = {'GODWATCH': 20000 + 300, 'GODWATCH_EVICTIM': 20000 + 2000 + 300}
bad_ev = [s for s in god if int(re.search(r'ev=(\d+)', s).group(1)) not in want.values()]
if bad_ev:
    print(f'INCONCLUSIVE: unexpected event in HIDE_GOD: {bad_ev[0]}'); sys.exit(2)
if len(god) < len(rolls):
    print(f'RED: {len(rolls)} rolls but only {len(god)} god-watch dispatches\n'
          f'Run: {run}'); sys.exit(1)
print(f'GREEN: {len(rolls)} rolls, {len(god)} god-watch dispatches for '
      f'EV_SPOT_CHECK ({len(god) // len(rolls)} per roll). Run: {run}')
PY
