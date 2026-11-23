#!/bin/bash
# gate: live
# inc-6lwjk: a watcher keeps a bounded number of spot-result notes, so a crowd of
# hiders cannot push one creature's status list past the engine cap of 256.
# (0 GREEN, 1 RED, 2 INCONCLUSIVE)
#
# THE ORACLE is INCURSION_HIDE_NOTE_PROBE, which arms HideNoteProbe
# (src/HideNoteProbe.cpp) at the top of Game::Play. One watcher runs a real
# SpotCheck against 100 other creatures, and the probe prints
#   HIDE_NOTE hiders=<n> notes=<n> newest=<0|1>
# Before the fix the watcher held one note per hider (notes=100). After it, the
# watcher holds HIDE_NOTE_MAX (32, inc/HideCheck.h) and keeps the newest note.
#
# GREEN: hiders=100, notes=32 and newest=1. RED: any other count.
# INCONCLUSIVE: no COMPLETE line, an INCONCLUSIVE line, or an abnormal exit.
#
# fact: character and map -- fixture orc-rogue-seed1-opt0822.char (INCURSION_LOAD)
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: the watcher and the 100 hiders -- placed by the probe, in free squares nearest the player
# fact: spot check verdicts -- not read; a note is stored whether the watcher spots or not
# fact: whether 100 free squares exist near the player -- the probe prints INCONCLUSIVE when they do not
#
# Usage: tools/check_hide_note_cap.sh [seed]
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo 'INCONCLUSIVE: build the posix backend'; exit 2; }
RUN="$(mktemp -d "$PWD/logs/hide-note-cap-XXXXXX")"
INCURSION_HIDE_NOTE_PROBE=1 INCURSION_RUN_DIR="$RUN" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.char \
    tools/headless.sh tools/keys/hide-note-cap.keys "${1:-1}" > "$RUN.out" 2>&1
status=$?
python3 - "$RUN" "$status" <<'PY'
import pathlib, re, sys
run = pathlib.Path(sys.argv[1])
log = run / 'logs/errors.log'
if not log.exists():
    print(f'INCONCLUSIVE: no probe log; {run}.out'); sys.exit(2)
lines = [s for s in log.read_text().splitlines()
         if not s.startswith('    ') and 'HIDE_NOTE' in s]
if any('INCONCLUSIVE' in s for s in lines) or not any('HIDE_NOTE COMPLETE' in s for s in lines):
    print(f'INCONCLUSIVE: incomplete probe; {run}.out'); sys.exit(2)
if int(sys.argv[2]) not in (0, 3):
    print(f'INCONCLUSIVE: headless exit {sys.argv[2]}; {run}.out'); sys.exit(2)
got = [re.search(r'HIDE_NOTE hiders=(\d+) notes=(\d+) newest=(\d)', s) for s in lines]
got = [m for m in got if m]
if len(got) != 1:
    print(f'INCONCLUSIVE: expected one result line; {run}.out'); sys.exit(2)
hiders, notes, newest = map(int, got[0].groups())
print(f'hiders={hiders} notes={notes} newest={newest}')
if hiders == 100 and notes == 32 and newest == 1:
    print('GREEN: notes capped at 32, newest kept'); sys.exit(0)
print(f'RED: expected hiders=100 notes=32 newest=1. Run: {run}'); sys.exit(1)
PY
