#!/bin/bash
# gate: live
# inc-ctee: Music of the Spheres reach and durations, measured live.
# Loaded priest at caster level 8, forced natural-1 saves, kobolds and jackals
# on one orthogonal line. Jackals at 2, 8 and 9 squares show paralysis; a
# kobold at 3 shows the god's condition (damage ends paralysis, so one
# creature cannot show both). The probe borrows each god in turn
# (INCURSION_MUSIC_AREA_PROBE_GOD): Essiah (nausea), Maeve (confusion), Mara
# (slow) and the fixture priest's own god (stun).
# Required, for each god: the 8-square jackal is paralyzed, the 9-square jackal
# is not, every PARALYSIS lasts 1..4 units, and the god's condition lasts
# 1 round per caster level converted once: (CL + choir) / 2 units, 4 at CL 8
# and 6 with a level-8 bardic ally (choir 4, CL 12). Two casts per session:
# no choir, then choir.
# The kobold (opposed alignment, CR<=5, hostile) must hold BOTH the condition
# and PARALYSIS 1..4 after damage (damage must not break the paralysis).
# FAIL, INCONCLUSIVE or missing results exit nonzero.
# fact: character -- fixture xsummon-priest-seed5-opt0822 (INCURSION_LOAD)
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: saves -- forced to natural 1 inside the probe
# fact: god -- INCURSION_MUSIC_AREA_PROBE_GOD names it
# fact: caster level -- the probe grants 8 itself; the choir ally is a level-8 bard
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

check_god() {
    local god="$1"
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-music-area-$god"
    INCURSION_MUSIC_AREA_PROBE=1 INCURSION_MUSIC_AREA_PROBE_GOD="$god" \
        INCURSION_RUN_DIR="$RUN_DIR" \
        INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
        tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1

    local log="$RUN_DIR/logs/errors.log"
    if [ ! -s "$log" ]; then
        echo "FAIL: $god: no $log. Is MusicAreaProbe still called from Game::Play()?"
        return 1
    fi

    local lines
    lines="$(grep 'MUSIC_AREA_PROBE:' "$log")"
    if [ -z "$lines" ]; then
        echo "FAIL: $god: $log has no MUSIC_AREA_PROBE lines."
        return 1
    fi

    echo "$lines"
    echo "Specimen: $log"

    if grep -qE 'MUSIC_AREA_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
        echo "FAIL: $god: at least one probe case failed or was inconclusive."
        return 1
    fi
    local dist n c
    for dist in 2 3 8 9; do
        n="$(grep -c "MUSIC_AREA_PROBE: choir=[04] dist=$dist " <<< "$lines")"
        if [ "$n" -ne 2 ]; then
            echo "FAIL: $god: dist=$dist measured $n times, want 2 (no choir, choir)."
            return 1
        fi
    done
    for c in 0 4; do
        if ! grep -q "MUSIC_AREA_PROBE: choir=$c kobold both=1 cr=" <<< "$lines"; then
            echo "FAIL: $god: choir=$c kobold did not hold both condition and paralysis."
            return 1
        fi
    done
    if ! grep -q 'MUSIC_AREA_PROBE: PASS' <<< "$lines"; then
        echo "FAIL: $god: missing PASS result."
        return 1
    fi
    echo "PASS: $god"
}

for god in Essiah Maeve Mara fixture; do
    check_god "$god" || exit 1
done

echo "PASS: reach is 8 squares, paralysis lasts 1..4, every god's condition lasts 1 round per caster level (converted once)."
