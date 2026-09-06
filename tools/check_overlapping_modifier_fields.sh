#!/bin/bash
# Regression check for inc-fiiq: overlapping same-effect mobile fields must not
# remove or reap one another, and duplicate grants must have one contributor.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BIN="${INCURSION_BIN:-./incursion-headless}"
EXPECT_WHITE="${INCURSION_EXPECT_WHITE:-2}"
[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_LIGHT_PROBE=1 INCURSION_BIN="$BIN" \
    INCURSION_OPTIONS=tools/gates/Options.Dat \
    tools/headless.sh tools/keys/overlapping-modifier-fields.keys 20260905 2>&1)"
status=$?
run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
late="$run/logs/screens/0001-late-stati.txt"
log="$run/logs/light.log"
if [ "$status" -ne 0 ] || printf '%s\n' "$out" | grep -q "NO GAMEPLAY" || \
   [ ! -f "$late" ] || [ ! -f "$log" ]; then
    echo "INCONCLUSIVE: fixture did not complete. Run dir: ${run:-unknown}"
    printf '%s\n' "$out"
    exit 2
fi

circle="$(grep -ci 'eID:Magic Circle vs\.' "$late")"
stamped_circle="$(grep -A3 'SAVE_BONUS from SS_ENCH' "$late" | \
    grep -c 'h:torch archon')"
white="$(python3 - "$log" <<'PY'
import sys
blocks = open(sys.argv[1]).read().split("LIGHT ")[1:]
if not blocks:
    raise SystemExit(2)
lines = blocks[-1].splitlines()[1:]
print(sum(line.startswith("S ") and
          line.split()[3:7] == ["2", "255", "255", "255"]
          for line in lines))
PY
)" || {
    echo "INCONCLUSIVE: unreadable final light block. Run dir: $run"
    exit 2
}

echo "overlap: white-radius-2=$white selected-circle-rows=$circle stamped-circle-rows=$stamped_circle"
if [ "$white" -ne "$EXPECT_WHITE" ] || [ "$circle" -ne 1 ] || \
   [ "$stamped_circle" -ne 1 ]; then
    echo "FAIL: overlapping torch archons lost a field or retained duplicate rows."
    echo "      Run dir: $run"
    exit 1
fi
echo "PASS: both overlapping torch-archon fields survive and one stamped circle row remains."
