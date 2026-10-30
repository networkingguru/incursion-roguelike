#!/bin/bash
# gate: cheap
# Regression check for the job pool in tools/soak.sh (inc-b0ziu).
#
# The defect. soak.sh throttled with `wait -n 2>/dev/null || wait`. macOS
# /bin/bash 3.2 has no `wait -n`, so the fallback waited for ALL jobs and the
# pool ran one session at a time after the first wave. A 40-session soak with
# SOAK_JOBS=4 summed 704 s of session time over a 643 s wall span.
#
# The check runs a copy of soak.sh against a stub headless.sh that sleeps 1 s.
# A working pool of 4 finishes 8 sessions in about 2 s; the broken one needs
# about 5 s. No game runs.
#
# fact: wall time of a stub soak -- stub headless.sh sleeps a fixed 1 s, no game runs
# fact: number of sessions finished -- the stub appends nothing; soak.sh writes `exits`
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/soak-parallel.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/tools"
cp "$ROOT/tools/soak.sh" "$T/tools/soak.sh"
printf '#!/bin/sh\nsleep 1\nexit 0\n' > "$T/tools/headless.sh"
printf '#!/bin/sh\nexit 0\n' > "$T/incursion-headless"
chmod +x "$T/tools/soak.sh" "$T/tools/headless.sh" "$T/incursion-headless"
: > "$T/empty.keys"

start=$SECONDS
SOAK_JOBS=4 SOAK_DIR="$T/out" "$T/tools/soak.sh" 8 1 "$T/empty.keys" > "$T/soak.log" 2>&1
wall=$((SECONDS - start))
lines="$(wc -l < "$T/out/exits" 2>/dev/null | tr -d ' ')"
lines="${lines:-0}"

if [ "$wall" -ge 4 ] || [ "$lines" -ne 8 ]; then
    echo "FAIL: 8 one-second sessions at SOAK_JOBS=4 took ${wall}s (need < 4s), exits lines: $lines (need 8)"
    exit 1
fi
echo "PASS: 8 one-second sessions at SOAK_JOBS=4 took ${wall}s, exits lines: $lines"
