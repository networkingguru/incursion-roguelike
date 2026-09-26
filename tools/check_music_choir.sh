#!/bin/bash
# gate: live
#
# inc-s3bb: live choir damage, Chain Lightning regression guard, and the
# maximized Shadow Step range produced by CalcEffect. Uses the frozen priest
# fixture with CA_SPELLCASTING raised to level 8. Every cast is maximized;
# damage casts force natural-1 saves. The bard contributes level 6 / 2.
# Case A retains its exact 4*CL + spell bonus assertion; case B adds 12.
# Chain Lightning must keep full damage on EVERY target: 6*CL + bonus, no
# per-arc reduction (the chain strikes all targets with the final arc count;
# see inc-5vfs).
# Shadow Step checks the vDmg range consumed by Travel without its prompt:
# SHADOW0 at the fixture's level 0 (expected 12), SHADOW3 with a temporary
# shadowdancer level 3 (hard-coded expected 18 = 12 + 2*3; the caster's
# ClassID[1]/Level[1] are saved and restored).
# All cases must PASS; FAIL, INCONCLUSIVE, or missing results exit nonzero.
# Usage: tools/check_music_choir.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/music-choir.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-music-choir"
out="$(INCURSION_MUSIC_CHOIR_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. The probe never wrote anything -- is"
    echo "      MusicChoirProbe still called from Game::Play()?"
    exit 1
fi

# errors.log timestamps every line and prints a one-time call stack after a
# message's first occurrence (tools/headless.sh convention), so match the
# marker as a substring, not an anchor.
lines="$(grep 'MUSIC_CHOIR_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no MUSIC_CHOIR_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"

# Here-strings avoid the pipe/SIGPIPE false-negative described in inc-wbq9.
if grep -qE 'MUSIC_CHOIR_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
for marker in 'PASS' 'CHAIN PASS' 'SHADOW0 PASS' 'SHADOW3 PASS'; do
    if ! grep -q "MUSIC_CHOIR_PROBE: $marker" <<< "$lines"; then
        echo "FAIL: missing result $marker"
        exit 1
    fi
done

echo "PASS: every music-choir probe case passed."
