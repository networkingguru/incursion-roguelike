#!/bin/bash
# Regression check for inc-fiiq: killing one archon must not darken the other.
#
# Two torch archons one square apart each sit inside the other's magic circle.
# The player kills the near one.  Map::RemoveField throws EV_FIELDOFF to every
# creature the dead field covered, so the survivor takes a leave event for a
# field that is not its own.  Before the fix that removed every row with the
# matching effect id -- the survivor's own included -- and Creature::StatiOff
# reaped the survivor's field.  The survivor stayed alive and went dark.
#
# Red oracle: on an unfixed binary the final white radius-2 count is 0, not 1.
#
# Usage: tools/check_circle_creator_death.sh (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BIN="${INCURSION_BIN:-./incursion-headless}"
KEYS=tools/keys/circle-creator-death.keys
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

log="$run/logs/light.log"
after="$(find "$run/logs/screens" -name '*-after-kill.txt' -print | head -1)"
[ -f "$log" ] && [ -n "$after" ] || {
    echo "INCONCLUSIVE: fixture produced no light log or no post-kill screen. Run dir: $run"
    exit 2
}

read -r peak final <<<"$(python3 - "$log" <<'PY'
import sys
blocks = open(sys.argv[1]).read().split("LIGHT ")[1:]
if not blocks:
    raise SystemExit(2)
def white(b):
    return sum(1 for l in b.splitlines()[1:]
               if l.startswith("S ") and l.split()[3:7] == ["2", "255", "255", "255"])
counts = [white(b) for b in blocks]
print(max(counts), counts[-1])
PY
)" || { echo "INCONCLUSIVE: could not read the light probe. Run dir: $run"; exit 2; }

# The survivor is the only torch archon still listed under "Things in View".
alive="$(sed -n '/Things in View/,$p' "$after" | grep -c 'A torch archon')"

echo "death: peak-white=$peak final-white=$final survivor-in-view=$alive"

fail=0
if [ "$peak" -ne 2 ]; then
    echo "FAIL: the fixture never had two lit archons (peak $peak); it proves nothing."
    fail=1
fi
if [ "$final" -ne 1 ]; then
    echo "FAIL: after one archon died the survivor's own light is $final, expected 1."
    fail=1
fi
if [ "$alive" -lt 1 ]; then
    echo "FAIL: no torch archon survived the kill; the fixture killed both."
    fail=1
fi

[ "$fail" -eq 0 ] || { echo "      Run dir: $run"; exit 1; }
echo "PASS: killing one archon left the survivor alive and still lit."
