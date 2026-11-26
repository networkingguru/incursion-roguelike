#!/bin/bash
# inc-i63lc: measure live SDL Fireball animation; never build binaries or record frames.
# fact: character -- fixture xsummon-priest-seed5-opt0822 (.char fixes attributes and kit)
# fact: terrain and targets -- EffectReelProbe builds its cleared room and three fixed kobolds; no game turns during the cast
# fact: target survival and equipment -- probe stages 30000 HP and removes all inventory before casting; spell damage is not asserted
# fact: saving throws -- INCURSION_FORCE_SAVE_ROLL=1
# fact: effect and aim -- existing EffectReelProbe Fireball cast and fixed middle-kobold target; no spell-success roll (EV_EFFECT)
# fact: animation option -- INCURSION_ANIM_SPEED_PROBE sets OPT_ANIMATION to 0, 1 or 2 (None) after loading
# fact: None span -- no flash starts under None, so its wall_ms runs from arming the probe to the cast's end, not first lit present; it holds ~27 ordinary UI presents, so AC3 asserts wait_ms (time inside waits), not wall_ms
# fact: visible motion -- SDL Update observes consecutive displayed map RGB states, including flight/fill/tail; no virtual recorder
# fact: duration -- steady_clock first lit present through final effect-end hook; wall time is reported, never thresholded
# fact: wait motion -- probe scope marks SleepTicking entry/exit; only presents inside count toward wait_states
# fact: phase motion -- last EffectLightHook/TargetFlashHook selects flight (before hooks), burst (EL_LIT/TF_LIT), or hold_tail (EL_HOLD/end)
# Exit 1: Fast wait_states <3 while Normal wait_states >=3.
# Exit 1 also: None (option 2) shows wait_presents > 0 or wait_ms >= 50 (time inside StopWatch sleeps; AC3: no animation is shown).
# Exit 0: Fast wait_states >=3 with a measurable Normal control.
# Exit 2: could not measure, including a Normal control with wait_states <3.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
for bin in incursion incursion-headless; do
    [ -x "./$bin" ] || { echo "Missing $bin; build it before running this script."; exit 2; }
done
unset INCURSION_FRAMES INCURSION_EFFECT_LIGHT_OFF INCURSION_EFFECT_LIGHT_TABLE
unset INCURSION_EFFECT_LIGHT_PROBE INCURSION_EFFECT_REEL INCURSION_REEL_SCENE_OFF
unset INCURSION_WALL_LOAD INCURSION_FIERY_ROOM
mkdir -p logs/anim-speed
OUT="$(mktemp -d "$ROOT/logs/anim-speed/run-XXXXXX")" || exit 2
echo "specimens: $OUT"
# Generate/load the .char with the POSIX binary, as render_effect_reel.sh does.
LOAD="$(INCURSION_BIN=./incursion-headless tools/fixture_cache.sh xsummon-priest-seed5-opt0822 2>"$OUT/fixture.err")" || exit 2
failed=0
for option in 0 1 2; do
    rd="$OUT/option-$option"
    mkdir -p "$rd"
    env INCURSION_BIN=./incursion INCURSIONFONTPATH="$ROOT/fonts" \
        INCURSION_RUN_DIR="$rd" INCURSION_LOAD="$LOAD" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        INCURSION_LIGHT_TABLE="$ROOT/tools/fixtures/effect-light-table.tsv" \
        INCURSION_ANIM_SPEED_PROBE="$option" INCURSION_FORCE_SAVE_ROLL=1 \
        INCURSION_MAP_AUDIT=0 INCURSION_SAVE_PROBE=0 \
        tools/headless.sh tools/keys/repro-anim-speed.keys 1 >"$rd/run.out" 2>&1
    rc=$?
    # The probe runs before the first completed game turn; @quit may yield 5.
    case "$rc" in 0|3|5) ;; *) echo "Option $option could not run (exit $rc): $rd/run.out"; failed=1 ;; esac
done
[ "$failed" -eq 0 ] || exit 2
python3 - "$OUT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
rows = []
metrics = ("presents", "states", "wall_ms", "wait_presents", "wait_states",
           "flight_presents", "flight_states", "burst_presents", "burst_states",
           "hold_tail_presents", "hold_tail_states", "wait_ms")
for option in (0, 1, 2):
    path = root / ('option-%d' % option) / 'logs/errors.log'
    text = path.read_text(errors='replace') if path.exists() else ''
    pattern = (r'ANIM_SPEED option=(?P<option>\d+) presents=(?P<presents>\d+) '
               r'states=(?P<states>\d+) wall_ms=(?P<wall_ms>[0-9]+\.[0-9]+) effect=Fireball'
               + ''.join(r' ' + key + r'=(?P<' + key + r'>\d+)' for key in metrics[3:-1]) + r' wait_ms=(?P<wait_ms>[0-9]+\.[0-9]+)')
    matches = list(re.finditer(pattern + r'(?![\w.])', text))
    if len(matches) != 1 or int(matches[0]['option']) != option or 'ANIM_SPEED_ERROR' in text:
        print('Could not measure: expected one valid result in', path)
        sys.exit(2)
    rows.append(matches[0].groupdict())
print('%-18s %14s %14s %14s' % ('metric', 'Normal (0)', 'Fast (1)', 'None (2)'))
for label in metrics:
    print('%-18s %14s %14s %14s' % (label, rows[0][label], rows[1][label], rows[2][label]))
if int(rows[0]['wait_states']) < 3:
    print('Could not measure: Normal control showed fewer than 3 wait states.')
    sys.exit(2)
bad = int(rows[1]['wait_states']) < 3
if int(rows[2]['wait_presents']) != 0 or float(rows[2]['wait_ms']) >= 50:
    print('None shows animation: wait_presents %s, wait_ms %s (need 0 and under 50).' % (rows[2]['wait_presents'], rows[2]['wait_ms']))
    bad = True
sys.exit(1 if bad else 0)
PY
