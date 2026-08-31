#!/bin/bash
# Regression check for inc-jcg4: dynamic external light participates in the
# shadow-hide warning and reveal gates even without static Bright or carried light.
# Usage: tools/check_hide_dynamic_light.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_LIGHT_PROBE=1 INCURSION_BIN="$BIN" tools/headless.sh tools/keys/hide-dynamic-light.keys 1 2>&1)"
status=$?
RUN="$(echo "$out" | awk '/^run:/ {print $2}')"

[ "$status" -eq 0 ] || {
    echo "INCONCLUSIVE: headless fixture exited $status. Run dir: $RUN"
    echo "$out"
    exit 2
}

before="$(ls "$RUN"/logs/screens/*dynamic-source-hidden* 2>/dev/null | head -1)"
warning="$(ls "$RUN"/logs/screens/*dynamic-light-warning* 2>/dev/null | head -1)"
after="$(ls "$RUN"/logs/screens/*after-dynamic-light-move* 2>/dev/null | head -1)"
log="$RUN/logs/light.log"
[ -f "$before" ] && [ -f "$warning" ] && [ -f "$after" ] && [ -f "$log" ] || {
    echo "INCONCLUSIVE: fixture wrote no before/warning/after dump or light probe. Run dir: $RUN"
    exit 2
}

grep -q 'Hiding' "$before" || {
    echo "INCONCLUSIVE: rogue was not hidden before entering dynamic light. Run dir: $RUN"
    exit 2
}
grep -Eq '^S [0-9]+ [0-9]+ 3 255 160 60 5 ' "$log" || {
    echo "INCONCLUSIVE: the live wall-torch source was not scanned. Run dir: $RUN"
    exit 2
}
last="$(grep '^P ' "$log" | tail -1)"
echo "$last" | grep -q 'plight=0 pbright=0 psource=\(9[0-9]\|[1-9][0-9][0-9]\) punified=1' || {
    echo "INCONCLUSIVE: destination was not dynamic-only bright light: $last"
    echo "      Run dir: $RUN"
    exit 2
}

fail=0
if grep -q 'Hiding' "$after"; then
    echo "FAIL: rogue remained Hiding after entering the live wall-torch radius."
    fail=1
fi
if ! grep -qi 'brightly-lit area' "$warning"; then
    echo "FAIL: dynamic external light did not produce the hide warning."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: a scanned wall-torch source warned and cleared Hiding without carried light."
    echo "      Run dir: $RUN"
    exit 0
fi
echo "      Run dir: $RUN"
exit 1
