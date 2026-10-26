#!/bin/bash
# gate: live
# inc-2mea: mount must be strictly larger than rider, with no upper limit.
# fact: character and initial world -- human-paladin-seed4-opt0822 fixture (INCURSION_LOAD)
# fact: settings -- options-2026-08-22.dat (INCURSION_OPTIONS)
# fact: terrain, room and other creatures -- probe clears map objects and builds a floor arena in named Winding Corridor; no turns or AI during measurement
# fact: mounts and types -- named tiger, elephant and pony resources, validated sizes/flags; case 3 pony receives ADJUST A_SIZ -1 without a roll
# fact: rider sizes and dwarf identity -- probe assigns named Dwarf;race and its racial monster IDs as character creation does for case 4 and ADJUST A_SIZ stati without rolls; validates actual sizes and MA_DWARF
# fact: Ride and CR eligibility -- EXTRA_SKILL SK_RIDE and ANIMAL_COMPANION link, no roll
# fact: mount attitude -- wizard Make Player Master of Monster path (MakeCompanion PHD_FREEBIE), no roll; asserts nonhostility
# fact: recalculation reaches size-change path -- distinct ADJUST_SAC A_SIZ +/-1 without roll, actual before/after sizes asserted; real CalcValues
# fact: mount admission and refusal text -- real EV_MOUNT, MOUNTED/MOUNT pair and live MsgHistory (no random names asserted)
# fact: dismount reason and final state -- live thrown message and reciprocal stati after CalcValues; no roll
set -eu
cd "$(dirname "$0")/.."
ROOT="$PWD"
mkdir -p logs/runs
RUN_DIR="$(mktemp -d "$ROOT/logs/runs/mount-size.XXXXXX")"
echo "Specimens: $RUN_DIR"
for case_id in 1 2 3 4 5 6; do
    status=0
    INCURSION_BIN="$ROOT/incursion-headless" \
    INCURSION_MOUNT_SIZE_PROBE="$case_id" INCURSION_RUN_DIR="$RUN_DIR/case-$case_id" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/human-paladin-seed4-opt0822.sav \
        tools/headless.sh tools/keys/template-alignment.keys 1 \
        > "$RUN_DIR/case-$case_id.harness.txt" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        echo "FAIL: case $case_id harness exit $status"
        exit 1
    fi
done
python3 -I - "$RUN_DIR" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
failed = []
for n in range(1, 7):
    path = root / f'case-{n}/logs/mount-size.log'
    line = path.read_text().strip() if path.exists() else 'MISSING PROBE LOG'
    print(line)
    m = re.fullmatch(r'case=(\d) rider=(\w+)->(\w+) mount=(\w+)\((\w+)\) mount_result="([^"]*)" mounted_after_recalc=(yes|no) outcome=(\w+) setup=([01]) pair=([01])', line)
    if not m:
        failed.append(n)
        continue
    case, before, after, name, size, result, mounted, outcome, setup, pair = m.groups()
    expected = {
        1: ('small', 'tiny', 'tiger', 'large', True, 'yes', 'stays'),
        2: ('small', 'small', 'elephant', 'huge', True, 'yes', 'unchanged'),
        3: ('small', 'small', 'pony', 'small', False, 'no', 'refused'),
        4: ('medium', 'medium', 'pony', 'medium', False, 'no', 'refused'),
        5: ('medium', 'large', 'tiger', 'large', True, 'no', 'thrown'),
        6: ('medium', 'small', 'tiger', 'large', True, 'yes', 'stays'),
    }[n]
    observed = (before, after, name, size, result == 'admitted', mounted, outcome)
    refusal_ok = n not in (3,4) or 'not large enough to support' in result
    if int(case) != n or observed != expected or setup != '1' or pair != '1' or not refusal_ok:
        failed.append(n)
if failed:
    sys.exit('FAIL: ruling violated or setup invalid in cases ' + ', '.join(map(str, failed)))
print('PASS: all six mount-size cases satisfy the ruling.')
PY
