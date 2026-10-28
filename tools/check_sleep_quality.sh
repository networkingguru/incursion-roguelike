#!/bin/bash
# gate: live
# inc-30ur: WQ_SLEEP was refused by QualityOK on every weapon and had no on-hit effect, so Kysul's blessed trident never got it.
# fact: character and initial world -- human-paladin-seed4-opt0822 fixture (INCURSION_LOAD)
# fact: settings -- options-2026-08-22.dat (INCURSION_OPTIONS)
# fact: terrain, room and other creatures -- probe clears map objects and builds a floor arena in named Winding Corridor; no turns or AI during measurement
# fact: weapons -- named trident and long sword resources, created by the probe; WQ_SLEEP added directly for cases 3-8, no roll
# fact: target creatures -- named giant rat and cave orc (sleep-susceptible) and cellar dwellar (sleep-immune); probe setup validates ResistLevel(AD_SLEE) and evil status per case, no roll
# fact: blessing path -- real Character::IBlessing; probe sets god Kysul and FavourLev 20 directly (no wizard Set Favour on master), +1 trident, no roll
# fact: attack path, cases 3-8 -- real Throw(EV_WATTACK) from the player to an adjacent target; probe wields the weapon and logs vRoll/vHit/vDef/isHit/isCrit read from the finished event
# fact: attack d20, cases 3-8 -- INCURSION_LOF_FORCE_ROLL=19 (a hit, below the trident's threat range; setup=0 on a crit or miss)
# fact: hit bonus and Defense Class -- fixture paladin and targets, no roll; setup=0 unless the logged margin vRoll+vHit-vDef is at least 5 (exactly 4 in case 5)
# fact: case 5 margin -- the probe gives the target +2 deflection (ADJUST_DEFL); the fixture's own margin is 6, so the real margin is 4; setup=0 unless the finished event shows exactly 4
# fact: miss chance and visibility -- probe lights both squares; targets have no miss-chance status; setup=0 on a wild miss
# fact: target's Fortitude save -- INCURSION_FORCE_SAVE_ROLL=1 (always fails) or 20 (case 4, always succeeds)
# fact: damage -- INCURSION_FORCE_DAMAGE_ROLL=1 and the probe sets target hit points to 1000, so the target lives; setup=0 unless it took damage
# fact: paladin holy pass, case 8 -- evil cave orc and good player validated in setup; setup=0 unless the finished event lists the holy damage (strXDmg has "holy")
# fact: sleep duration -- not asserted exactly (3d4 roll); asserts ASLEEP duration in 3..12
# fact: message text -- only fixed substrings "deep silvery light" and "falls asleep." are matched, never a random name
# Exit 0 pass, 1 fail, 2 could not measure.
set -u
cd "$(dirname "$0")/.."
ROOT="$PWD"
[ -x ./incursion-headless ] || { echo "could not measure: build with BACKEND=posix ./build_macos.sh"; exit 2; }
mkdir -p logs/runs
RUN_DIR="$(mktemp -d "$ROOT/logs/runs/sleep-quality.XXXXXX")"
echo "Specimens: $RUN_DIR"
for case_id in 1 2 3 4 5 6 7 8; do
    save=1; [ "$case_id" = 4 ] && save=20
    lof=; dmg=; [ "$case_id" -ge 3 ] && { lof=19; dmg=1; }
    status=0
    INCURSION_BIN="$ROOT/incursion-headless" \
    INCURSION_SLEEP_QUALITY_PROBE="$case_id" INCURSION_RUN_DIR="$RUN_DIR/case-$case_id" \
    INCURSION_FORCE_SAVE_ROLL="$save" \
    INCURSION_LOF_FORCE_ROLL="$lof" INCURSION_FORCE_DAMAGE_ROLL="$dmg" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/human-paladin-seed4-opt0822.sav \
        tools/headless.sh tools/keys/template-alignment.keys 1 \
        > "$RUN_DIR/case-$case_id.harness.txt" 2>&1 || status=$?
    # Cases 3-8 can leave a wounded target; the harness then calls the run NO
    # GAMEPLAY (exit 5). The probe log, written at start-up, is the measurement.
    [ "$case_id" -ge 3 ] && [ "$status" = 5 ] && status=0
    if [ "$status" -ne 0 ]; then
        echo "could not measure: case $case_id harness exit $status"
        exit 2
    fi
done
python3 -I - "$RUN_DIR" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
failed, missing = [], []
for n in range(1, 9):
    path = root / f'case-{n}/logs/sleep-quality.log'
    line = path.read_text().strip() if path.exists() else ''
    print(line or f'case {n}: MISSING PROBE LOG')
    if n == 1:
        m = re.fullmatch(r'case=1 trident_ok=(\d) sword_ok=(\d) setup=(\d)', line)
        ok = m and m.groups() == ('1', '1', '1')
    elif n == 2:
        m = re.fullmatch(r'case=2 has_sleep=(\d) glow=(\d) setup=(\d)', line)
        ok = m and m.groups() == ('1', '1', '1')
    else:
        m = re.fullmatch(r'case=(\d) asleep=(\d) dur=(\d+) said=(\d) resist=(\d) immune=(\d) margin=(-?\d+) setup=(\d) '
                         r'vRoll=(\d+) vHit=(-?\d+) vDef=(-?\d+) vThreat=(\d+) isHit=(\d) isCrit=(\d) hurt=(\d) holy=(\d)', line)
        ok = False
        if m:
            _, asleep, dur, said, resist, immune, margin, setup = m.groups()[:8]
            dur = int(dur)
            slept = lambda: asleep == '1' and 3 <= dur <= 12 and said == '1' and resist == '0' and immune == '0'
            expect = {
                3: slept, 7: slept, 8: slept,
                4: lambda: asleep == '0' and said == '0' and resist == '1',
                5: lambda: asleep == '0' and said == '0' and resist == '0' and immune == '0',
                6: lambda: asleep == '0' and said == '0' and immune == '1',
            }[n]
            ok = setup == '1' and expect()
    if not m:
        missing.append(n)
    elif not ok:
        failed.append(n)
if missing:
    print('could not measure: no valid log line for cases ' + ', '.join(map(str, missing)))
    sys.exit(2)
if failed:
    print('FAIL: WQ_SLEEP ruling violated or setup invalid in cases ' + ', '.join(map(str, failed)))
    sys.exit(1)
print('PASS: all eight WQ_SLEEP cases satisfy the ruling.')
PY
