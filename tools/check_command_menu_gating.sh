#!/bin/bash
# Defends inc-q0w0: command menus hide missing implementations and unmet prerequisites.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

out="$(INCURSION_OPTIONS=tools/gates/Options.Dat \
    tools/headless.sh tools/keys/command-menu-gating.keys 1 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: key script could not find an expected screen; run: $run"
    exit 2
fi

before="$run/logs/screens/0002-combat-without-feat.txt"
after="$run/logs/screens/0006-combat-with-feat.txt"
ybefore="$run/logs/screens/0003-yuse-without-feat.txt"
yafter="$run/logs/screens/0007-yuse-with-feat.txt"
for screen in "$before" "$after" "$ybefore" "$yafter"; do
    [ -f "$screen" ] || { echo "INCONCLUSIVE: missing screen: $screen"; exit 2; }
done

fail=0
if grep -q "Whirlwind Attack" "$before"; then
    echo "FAIL: C offers Whirlwind Attack without the feat"
    fail=1
fi
if ! grep -q "Whirlwind Attack" "$after"; then
    echo "FAIL: C hides Whirlwind Attack after the Quickblade grants the feat"
    fail=1
fi
for screen in "$ybefore" "$yafter"; do
    if grep -Eq '\] (Burn|Clean|Called Shot)( |$)' "$screen"; then
        echo "FAIL: a command with no implementation is visible in $screen"
        fail=1
    fi
done

if [ "$fail" = 0 ]; then
    echo "PASS: command menus hide missing implementations and unmet prerequisites"
    exit 0
fi
exit 1
