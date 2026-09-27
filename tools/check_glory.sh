#!/bin/bash
# gate: live
# inc-g1q1: bolt cap/fear, redirected DCs, and both metamagic half-words.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/glory.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-glory"
out="$(INCURSION_GLORY_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run_status=$?

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. The probe never wrote anything -- is"
    echo "      GloryProbe still called from Game::Play()?"
    exit 1
fi

# errors.log timestamps every line and prints a one-time call stack after a
# message's first occurrence (tools/headless.sh convention), so match the
# marker as a substring, not an anchor.
lines="$(grep 'GLORY_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no GLORY_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"
if [ "$run_status" -ne 0 ]; then
    echo "$out"
    echo "FAIL: headless exited $run_status"
    exit 1
fi

# Here-strings avoid the pipe/SIGPIPE false-negative described in inc-wbq9.
if grep -qE 'GLORY_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
for marker in 'cap .* PASS' 'save forced=pass fear=0 .* PASS' 'save forced=fail fear=1 .* PASS' 'dc child=Bolt of Glory .* PASS' 'dc child=Flame Arrow;blast .* PASS' 'dc child=Pyrotechnics;smoke .* PASS' 'dc child=Pyrotechnics;flash .* PASS' 'mm child=Bolt of Glory .* PASS' 'mm child=Flame Arrow;blast .* PASS' 'mm-scale child=Bolt of Glory .* PASS' 'mm-scale child=Flame Arrow;blast .* PASS' 'fullspell .* PASS' 'shadows .* PASS'; do
    if ! grep -qE "GLORY_PROBE: $marker$" <<< "$lines"; then
        echo "FAIL: missing result $marker"
        exit 1
    fi
done

echo "PASS: bolt cap, Will saves, child/full-spell DCs, metamagic, and Animate Shadows."
