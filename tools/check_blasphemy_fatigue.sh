#!/bin/bash
# gate: live
# inc-fdi2: one fatigue payment per area cast, negative fatigue and refusal.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/blasphemy_fatigue.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-blasphemy_fatigue"
out="$(INCURSION_BLASPHEMY_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run_status=$?

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. The probe never wrote anything -- is"
    echo "      BlasphemyProbe still called from Game::Play()?"
    exit 1
fi

# errors.log timestamps every line and prints a one-time call stack after a
# message's first occurrence (tools/headless.sh convention), so match the
# marker as a substring, not an anchor.
lines="$(grep 'BLASPHEMY_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no BLASPHEMY_PROBE lines."
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
if grep -qE 'BLASPHEMY_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
for marker in 'paid .* PASS' 'one-fatigue .* PASS' 'declined .* PASS'; do
    if ! grep -qE "BLASPHEMY_PROBE: $marker$" <<< "$lines"; then
        echo "FAIL: missing result $marker"
        exit 1
    fi
done

echo "PASS: Blasphemy charges two fatigue once, reaches both targets, and honours refusal."
