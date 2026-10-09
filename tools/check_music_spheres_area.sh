#!/bin/bash
# gate: live
# inc-ctee: Music of the Spheres reach and durations, measured live.
# Loaded priest at caster level 8, forced natural-1 saves, kobolds and jackals
# on one orthogonal line. Jackals at 2, 8 and 9 squares show paralysis; a
# kobold at 3 shows the god's condition (damage ends paralysis, so one
# creature cannot show both). The probe borrows Essiah (NAUSEA) because the
# fixture god's plain-stun branch ignores its duration argument.
# Required: the 8-square jackal is paralyzed, the 9-square jackal is not,
# every PARALYSIS lasts 1..4, and the condition lasts 10+2*CL (+2*3 with a
# level-6 bardic ally). Two casts per session: no choir, then choir.
# The kobold (opposed alignment, CR<=5, hostile) must hold BOTH the condition
# and PARALYSIS 1..4 after damage (damage must not break the paralysis).
# Expected red until the separate spell-data fix. FAIL, INCONCLUSIVE or
# missing results exit nonzero.
# Usage: tools/check_music_spheres_area.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/bane-radius.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-music-area"
INCURSION_MUSIC_AREA_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. Is MusicAreaProbe still called from Game::Play()?"
    exit 1
fi

lines="$(grep 'MUSIC_AREA_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no MUSIC_AREA_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"

if grep -qE 'MUSIC_AREA_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
for dist in 2 3 8 9; do
    n="$(grep -c "MUSIC_AREA_PROBE: choir=[03] dist=$dist " <<< "$lines")"
    if [ "$n" -ne 2 ]; then
        echo "FAIL: dist=$dist measured $n times, want 2 (no choir, choir)."
        exit 1
    fi
done
for c in 0 3; do
    if ! grep -q "MUSIC_AREA_PROBE: choir=$c kobold both=1 cr=" <<< "$lines"; then
        echo "FAIL: choir=$c kobold did not hold both condition and paralysis."
        exit 1
    fi
done
if ! grep -q 'MUSIC_AREA_PROBE: PASS' <<< "$lines"; then
    echo "FAIL: missing PASS result."
    exit 1
fi

echo "PASS: reach is 8 squares, paralysis lasts 1..4, condition keeps 10+2*CL."
