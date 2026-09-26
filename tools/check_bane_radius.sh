#!/bin/bash
# gate: live
# inc-7xcu: live Bane radius; expected red until the separate spell-data fix.
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

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-bane-radius"
out="$(INCURSION_BANE_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. The probe never wrote anything -- is"
    echo "      BaneRadiusProbe still called from Game::Play()?"
    exit 1
fi

# errors.log timestamps every line and prints a one-time call stack after a
# message's first occurrence (tools/headless.sh convention), so match the
# marker as a substring, not an anchor.
lines="$(grep 'BANE_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no BANE_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"

# Here-strings avoid the pipe/SIGPIPE false-negative described in inc-wbq9.
if grep -qE 'BANE_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
for marker in 'dist=5 affected=1' 'dist=6 affected=0' 'dist=7 affected=0' 'dist=9 affected=0' 'PASS'; do
    if ! grep -qE "BANE_PROBE: $marker$" <<< "$lines"; then
        echo "FAIL: missing result $marker"
        exit 1
    fi
done

echo "PASS: Bane affects distance 5 but not 6, 7 or 9."
