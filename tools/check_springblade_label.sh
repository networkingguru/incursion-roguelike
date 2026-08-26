#!/bin/bash
# Regression check for the Springblade Bracers type-3 display label,
# bd inc-tek.8.8.
#
# Seed 6 rolls type 3, whose two blades both receive inherent plus 2. The
# activation menu prints the item's full player-visible name, including the
# EV_GETNAME suffix. It must therefore say (+2 flame/+2 frost), not +3 flame.
#
# Usage: tools/check_springblade_label.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh tools/keys/springblade-label-probe.keys 6 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
screen="$run/logs/screens/0001-0001-label.txt"

if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script could not reach the bracers. Run: $run"
    exit 2
fi
if echo "$out" | grep -q "NO GAMEPLAY" || [ ! -f "$screen" ]; then
    echo "INCONCLUSIVE: the run produced no gameplay label screen. Run: $run"
    exit 2
fi

if grep -Fq "Springblade Bracers (+2 flame/+2 frost)" "$screen"; then
    echo "PASS: seed 6 names the type-3 pair (+2 flame/+2 frost)."
    exit 0
fi

label="$(grep -o 'Springblade Bracers ([^)]*)' "$screen" | head -1)"
echo "FAIL: seed 6 should name the type-3 pair (+2 flame/+2 frost)."
echo "      printed: ${label:-<no Springblade Bracers label>}"
echo "      dump: $screen"
exit 1
