#!/bin/bash
# Regression check for inc-hzy1: a modifier field's status inherits its duration.
#
# A directly placed torch archon owns one permanent field that is both its
# white light and its Magic Circle vs. Evil aura.  After about 4,800 turns the
# living, non-SUMMONED archon must still have both the field and the status.
#
# Usage: tools/check_field_modifier_duration.sh (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BIN="${INCURSION_BIN:-./incursion-headless}"
KEYS=tools/keys/field-modifier-duration.keys
SEED=20260905

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_LIGHT_PROBE=1 INCURSION_BIN="$BIN" \
    INCURSION_OPTIONS=tools/gates/Options.Dat \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
status=$?
run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
if [ "$status" -ne 0 ] || printf '%s\n' "$out" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: fixture exited $status. Run dir: ${run:-unknown}"
    printf '%s\n' "$out"
    exit 2
fi

late="$(find "$run/logs/screens" -name '*-late-stati.txt' -print | head -1)"
log="$run/logs/light.log"
[ -n "$late" ] && [ -f "$log" ] || {
    echo "INCONCLUSIVE: fixture produced no late status screen or light log. Run dir: $run"
    exit 2
}

alive=0
summoned=0
circle=0
white=0
grep -q 'With priority 1 it wanders about' "$late" && alive=1
grep -q 'SUMMONED' "$late" && summoned=1
grep -qi 'Magic Circle vs\.' "$late" && circle=1
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
    echo "INCONCLUSIVE: could not read the final light-probe block. Run dir: $run"
    exit 2
}

echo "late: alive=$alive summoned-status=$summoned white-light=$white magic-circle=$circle"
if [ "$alive" -ne 1 ] || [ "$summoned" -ne 0 ] || \
   [ "$white" -ne 1 ] || [ "$circle" -ne 1 ]; then
    echo "FAIL: the living, non-SUMMONED torch archon lost its permanent field or status."
    echo "      Run dir: $run"
    exit 1
fi

echo "PASS: the living torch archon retained its light field and Magic Circle status."
