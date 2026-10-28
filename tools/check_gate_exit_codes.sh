#!/bin/bash
# gate: cheap
# Prove that tools/gate_compare.sh fails a session that crashes on a signal.
# It builds a fake soak (one session exit 139, SIGSEGV) against
# tools/gates/dive.baseline (exits 0=40). It does not run the game.
# Usage: tools/check_gate_exit_codes.sh [gate_compare.sh to test]  (0 pass, 1 fail)
#
# fact: baseline exit tally -- tools/gates/dive.baseline, "exits 0=40"
# fact: the soak -- fabricated here: 40 sessions, session 5 exit 139, no logs
# fact: options and seeds -- not read; --from skips the options check and the game
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GC="${1:-tools/gate_compare.sh}"
W="$(mktemp -d "${TMPDIR:-/tmp}/incursion-exitcodes.XXXXXX")"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/soak"
for i in $(seq 1 40); do
    if [ "$i" -eq 5 ]; then echo "$i 139"; else echo "$i 0"; fi
done > "$W/soak/exits"
if "$GC" --from "$W/soak" tools/gates/dive.baseline > "$W/out" 2>&1; then
    echo "FAIL: a session that crashed on signal 11 passed the gate"
    exit 1
fi
if ! grep -q "REGRESSION: 1 sessions crashed on signal 11, baseline had 0" "$W/out"; then
    echo "FAIL: the gate failed, but not with the crash REGRESSION line"
    exit 1
fi
echo "PASS: the gate fails a session that crashed on signal 11"
