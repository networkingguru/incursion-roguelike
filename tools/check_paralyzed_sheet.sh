#!/bin/bash
# gate: live
# A paralyzed player can open the character sheet and Conditions (inc-sg8d4).
# fact: character and starting world -- fixture orc-barbarian-seed1-opt0822
# fact: no monster interference -- wizard Genocide Everything before search
# fact: paralysis -- scratch god, GainTempStati PARALYSIS duration 100; control
#       is the prompt text in the first dump (Player.cpp IsParalyzed)
# fact: settings -- frozen options-2026-08-22.dat
# fact: time -- turn number in each dump's first line; control is that
#       the final "1" (wait 10) advances it
# fact: sheet shown -- "Gender" line (sheet front page); control: absent in
#       the prompt and ignored dumps
# fact: Conditions shown -- marker "special conditions at present" or
#       "Condition:" (Conditions dialog only; master lists no entry for a
#       paralysis from SS_ATTK, inc-9m0e); control: absent in the sheet dump
# fact: session completed -- headless exit 0 and ended: cleanly
# fact: prompt rendering -- the message line is 64 columns wide; the full
#       prompt plus " [pmd123]" (59 chars) MUST sit on one rendered line
#
# tools/check_paralyzed_sheet.sh [seed] (default 1)
# Exit 0: every assertion holds; 1: an assertion failed with all controls
# holding; 2: could not measure. Specimens stay under logs/runs/.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail_control() { echo "INCONCLUSIVE: $*"; exit 2; }
[ -x ./incursion-headless ] || fail_control 'build with BACKEND=posix ./build_macos.sh'
SEED="${1:-1}"
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav
[ -f "$OPTIONS" ] && [ -f "$FIXTURE" ] || fail_control 'missing frozen fixture'
BASE="$ROOT/logs/runs/check-paralyzed-sheet-$(date +%s)-$$"
RUN="$BASE/run"
mkdir -p "$BASE/module/mod" "$BASE/module/logs" "$RUN/mod" "$RUN/lib" || fail_control 'mkdir failed'
echo "specimens: $BASE"
cp -Rf "$ROOT/lib" "$BASE/module/lib" || fail_control 'copy lib failed'
ln -s "$ROOT/inc" "$BASE/module/inc" || fail_control 'link inc failed'
cat tools/fixtures/paralyzed-sheet-god.irh >> "$BASE/module/lib/main.irc"
INCURSIONPATH="$BASE/module/" ./incursion-headless -compile main.irc \
    < /dev/null > "$BASE/module/compile.log" 2>&1
[ "$?" -eq 0 ] && [ -s "$BASE/module/mod/Incursion.Mod" ] || \
    fail_control "scratch compile failed; see $BASE/module/compile.log"
cp -f "$BASE/module/mod/Incursion.Mod" "$RUN/mod/Incursion.Mod" || fail_control 'copy module failed'
INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$FIXTURE" \
    tools/headless.sh tools/keys/paralyzed-sheet.keys "$SEED" > "$RUN/session.txt" 2>&1
echo "$?" > "$RUN/exit-code.txt"
python3 - "$RUN" <<'PYCODE'
import pathlib, re, sys
run = pathlib.Path(sys.argv[1])
errors, fails = [], []
if (run / 'exit-code.txt').read_text().strip() != '0' or \
        not re.search(r'ended: +cleanly', (run / 'session.txt').read_text()):
    errors.append('session did not end cleanly')
names = ['prompt', 'ignored', 'sheet', 'conditions', 'back', 'waited']
d = {}
for n in names:
    hits = sorted((run / 'logs/screens').glob(f'*-{n}.txt'))
    if len(hits) != 1:
        errors.append(f'dump {n}: found {len(hits)}')
    else:
        d[n] = hits[0].read_text()
if errors:
    print('INCONCLUSIVE: ' + '; '.join(errors)); sys.exit(2)
turn = {n: (re.search(r' turn (\d+) ===', t) or [None, None])[1] for n, t in d.items()}
if None in turn.values():
    print('INCONCLUSIVE: turn unreadable ' + repr(turn)); sys.exit(2)
flat = {n: re.sub(r'\s+', ' ', t) for n, t in d.items()}
PROMPT = 'Paralyzed: pray, magic, wait 10/20/30, or d for sheet? [pmd123]'
rendered = [l for l in d['prompt'].splitlines() if re.search(r'Paralyzed:|sheet\?|wait 10', l)]
print('rendered prompt lines: ' + repr(rendered))
# Controls
if 'Gender' in d['prompt'] or 'Gender' in d['ignored']:
    errors.append('control: Gender already on screen before d')
COND = re.compile(r'special conditions at present|Condition:')
if COND.search(d['sheet']):
    errors.append('control: Condition: already on the sheet')
if int(turn['waited']) <= int(turn['back']):
    errors.append(f'control: turn did not advance after 1 ({turn["back"]} -> {turn["waited"]})')
if errors:
    print('INCONCLUSIVE: ' + '; '.join(errors)); sys.exit(2)
if not any(PROMPT in l for l in d['prompt'].splitlines()):
    fails.append('(a) new prompt text absent')
if not (turn['ignored'] == turn['prompt'] and PROMPT in flat['ignored']
        and d['ignored'].splitlines()[1:] == d['prompt'].splitlines()[1:]):
    fails.append('(b) non-offered keys changed screen/turn or left the prompt')
if 'Gender' not in d['sheet'] or turn['sheet'] != turn['prompt']:
    fails.append('(c) d did not show the sheet at the same turn')
if not COND.search(d['conditions']) or turn['conditions'] != turn['prompt']:
    fails.append('(d) C did not show Conditions at the same turn')
if PROMPT not in flat['back'] or turn['back'] != turn['prompt']:
    fails.append('(e) prompt not back after ESC at the same turn')
print('turns: ' + repr(turn))
if fails:
    print('FAIL: ' + '; '.join(fails) + '; controls hold'); sys.exit(1)
print('PASS: paralyzed player opens sheet and Conditions, closes them, time unchanged')
PYCODE
