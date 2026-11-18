#!/bin/bash
# gate: live
# Conditions omits attack-source maladies (inc-9m0e); reproduction only.
# fact: character and starting world -- fixture orc-barbarian-seed1-opt0822 (INCURSION_LOAD)
# fact: no monster interference -- wizard Genocide Everything before search
# fact: one timed non-spell malady -- scratch blessing GainTempStati, SS_ATTK,
#       duration 100, Val/Mag 0, eID 0; explicit setup authorized by inc-9m0e
# fact: settings -- frozen options-2026-08-22.dat
# fact: active malady at sheet entry -- status dump immediately before d,C;
#       require its health label and the same turn in the Conditions dump
# fact: Conditions reached -- expect Gender on sheet, then C; require dialog
#       mode and a box border in the Conditions dump
# fact: session completed -- headless exit 0 and ended: cleanly
# fact: dialog text extent -- matching box borders and vertical sides; exclude
#       underlying sheet (including the test god name)
# fact: oracle text -- fixed UI labels and description phrases, not RNG text
# fact: paralysis -- timed PARALYSIS, SS_ATTK, duration 100; control is the
#       prompt text "Paralyzed: pray, magic, wait 10/20/30, or d for sheet?"
#       in the status dump (Player.cpp:553) and the Paralyzed sidebar label;
#       d, C then reach Conditions (inc-sg8d4)
# fact: nausea -- timed NAUSEA, SS_ATTK, duration 100; control is the "Nausea"
#       label on the bottom status line (StatiLineStats, src/Tables.cpp)
# fact: hunger -- scratch blessing SetStatiDur(HUNGER,-1,NULL,2000), band
#       1001-2750; one Search first so the sidebar repaints; control is the
#       Hungry sidebar label (the fixture is also Hungry unaided)
#
# tools/check_conditions_attack.sh [seed] (default 1)
# Exit 0: every label present; 1: missing label with ALL controls holding;
# 2: could not measure. Each malady runs separately (health is an else-if).
# All scratch modules, transcripts, saves and dumps stay under logs/.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail_control() { echo "INCONCLUSIVE: $*"; exit 2; }
[ -x ./incursion-headless ] || fail_control 'build with BACKEND=posix ./build_macos.sh'
SEED="${1:-1}"
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char
[ -f "$OPTIONS" ] && [ -f "$FIXTURE" ] || fail_control 'missing frozen fixture'
BASE="$ROOT/logs/runs/check-conditions-attack-$(date +%s)-$$"
mkdir -p "$BASE/module/mod" "$BASE/module/logs" || fail_control 'mkdir failed'
echo "specimens: $BASE"
cp -Rf "$ROOT/lib" "$BASE/module/lib" || fail_control 'copy lib failed'
ln -s "$ROOT/inc" "$BASE/module/inc" || fail_control 'link inc failed'
cat tools/fixtures/conditions-attack-gods.irh >> "$BASE/module/lib/main.irc"
INCURSIONPATH="$BASE/module/" ./incursion-headless -compile main.irc \
    < /dev/null > "$BASE/module/compile.log" 2>&1
[ "$?" -eq 0 ] && [ -s "$BASE/module/mod/Incursion.Mod" ] || \
    fail_control "scratch compile failed; see $BASE/module/compile.log"
# Real directories prevent headless.sh's symlink setup from replacing the
# scratch module; this is the existing heal-maladies scratch-module pattern.
for condition in stun blind confused paralyzed nauseated hungry; do
    RUN="$BASE/$condition"
    mkdir -p "$RUN/mod" "$RUN/lib" || fail_control 'mkdir run failed'
    cp -f "$BASE/module/mod/Incursion.Mod" "$RUN/mod/Incursion.Mod" || fail_control 'copy module failed'
    INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$FIXTURE" \
        tools/headless.sh "tools/keys/conditions-attack-$condition.keys" "$SEED" \
        > "$RUN/session.txt" 2>&1
    rc=$?
    # Run every session before evaluating controls or the oracle.
    echo "$rc" > "$RUN/exit-code.txt"
done
python3 - "$BASE" <<'PYCODE'
import pathlib, re, sys
base = pathlib.Path(sys.argv[1])
# name, heading, control regex on the status dump, fixed description phrase,
# timed attack-source (heading must show duration N > 0; a source is
# optional, but if "from" appears it must name something).
SESSIONS = [
    ('stun', 'Stunned', r'\|Stunned\s*$', 'Half of their attacks miss wildly', True),
    ('blind', 'Blind', r'\|Blind\s*$', 'Sight, Shadow and Darkvision ranges are all 0', True),
    ('confused', 'Confused', r'\|Confused\s*$', 'move in a randomly selected direction', True),
    ('nauseated', 'Nauseated', r'Nausea\s*\|', 'cannot attack or use innate abilities', True),
    ('hungry', 'Hungry', r'\|Hungry\s*$', 'maximum Fatigue Points drop by 1', False),
    ('paralyzed', 'Paralyzed', r'(?s)\A(?=.*Paralyzed: pray, magic, wait 10/20/30, or d for sheet\?)(?=.*\|Paralyzed[ ]*\n)', 'strike a coup de grace on a living victim', True),
]
missing, errors = [], []
for name, label, control, phrase, timed in SESSIONS:
    run = base / name
    transcript = (run / 'session.txt').read_text()
    if (run / 'exit-code.txt').read_text().strip() != '0' or not re.search(r'ended: +cleanly', transcript):
        errors.append(f'{name}: session did not end cleanly')
        continue
    screens = run / 'logs/screens'
    status, conditions = screens / '0001-status.txt', screens / '0002-conditions.txt'
    if not status.is_file() or not conditions.is_file():
        errors.append(f'{name}: missing dumps')
        continue
    before, after = status.read_text(), conditions.read_text()
    if ' mode 2 ' not in before.splitlines()[0] or not re.search(control, before, re.M):
        errors.append(f'{name}: status control absent')
    turns = [re.search(r' turn (\d+) ===', text) for text in (before, after)]
    if not all(turns) or turns[0][1] != turns[1][1]:
        errors.append(f'{name}: time passed between status and Conditions')
    # MO_DIALOG is 9 (inc/Term.h); isolate TextTerm::Box, not its backdrop.
    lines = after.splitlines()
    borders = [(i, m.start(), m.end() - 1) for i, line in enumerate(lines)
               for m in re.finditer(r'#-+#', line)]
    body = None
    if ' mode 9 ' in lines[0] and len(borders) == 2:
        (top, left, right), (bottom, left2, right2) = borders
        if (left, right) == (left2, right2) and bottom > top + 1:
            interior = lines[top + 1:bottom]
            if all(len(line) > right and line[left] == line[right] == '|' for line in interior):
                body = '\n'.join(line[left + 1:right] for line in interior)
    if body is None:
        errors.append(f'{name}: Conditions dialog not reached or box not readable')
    else:
        flat = re.sub(r'\s+', ' ', body)
        heading = re.search(r'^\s*Condition:\s*' + label + r'\b(.*)$', body, re.M)
        bad = []
        if not heading:
            bad.append('no heading ' + label)
        elif timed and not re.search(r'duration ([1-9]\d*)', heading[1]):
            bad.append(f'heading lacks duration: {heading[0].strip()!r}')
        elif re.search(r'\bfrom\b', heading[1]) and not re.search(r'from \S', heading[1]):
            bad.append(f'heading has empty source: {heading[0].strip()!r}')
        if name == 'hungry' and 'his Constitution' not in flat:
            bad.append('pronoun not substituted (want "his Constitution")')
        if phrase not in flat:
            bad.append(f'no description phrase {phrase!r}')
        if bad:
            missing.append(label)
            print(f'defect: {label}: {"; ".join(bad)}; box says {flat.strip()[:80]!r}')
    print(f'control: {name}: turn={turns[0][1] if turns[0] else "unknown"}; {conditions}')
if errors:
    print('INCONCLUSIVE: ' + '; '.join(errors))
    sys.exit(2)
if missing:
    print('FAIL: Conditions lacks entry/source/duration/description for ' + ', '.join(missing) + '; all session/status/dialog controls hold')
    sys.exit(1)
print('PASS: Conditions lists Stunned, Blind, Confused, Nauseated, Hungry and Paralyzed with duration and description')
PYCODE
