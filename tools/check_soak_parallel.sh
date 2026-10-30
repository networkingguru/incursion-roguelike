#!/bin/bash
# gate: cheap
# Regression check for the job pool in tools/soak.sh (inc-b0ziu).
#
# The defect. soak.sh throttled with `wait -n 2>/dev/null || wait`. macOS
# /bin/bash 3.2 has no `wait -n`, so the fallback waited for ALL jobs and the
# pool ran one session at a time after the first wave. A 40-session soak with
# SOAK_JOBS=4 summed 704 s of session time over a 643 s wall span.
#
# The check runs a copy of soak.sh against a stub headless.sh that sleeps 2 s
# and logs a start and an end line, each with a high-resolution timestamp. It
# sweeps those events for the most sessions alive at one moment AFTER the first
# session ends (the refill). A working pool of 4 refills to 4; the broken one
# refills to 1. The first wave alone reaches 4 under either pool, so it is not
# counted. Load stretches time but does not
# change that count. No game runs.
#
# fact: peak sessions alive at once after the first session ends -- stub headless.sh logs start/end times, no game runs
# fact: number of sessions finished -- soak.sh writes one `exits` line per session
#
# --selftest: mutate the soak.sh copy back to the old wait-all throttle and
#   expect this check to fail (exit 0 when it does).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/soak-parallel.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT

if [ "${1:-}" = "--selftest" ]; then
    SOAK_PARALLEL_MUTATE=wait-all "$0" > /dev/null 2>&1
    if [ "$?" -ne 1 ]; then
        echo "FAIL: selftest: the wait-all mutation did not fail the check with exit 1"; exit 1
    fi
    echo "PASS: selftest: the wait-all mutation fails the check"; exit 0
fi

JOBS=4
mkdir -p "$T/tools"
cp "$ROOT/tools/soak.sh" "$T/tools/soak.sh"
if [ "${SOAK_PARALLEL_MUTATE:-}" = "wait-all" ]; then
    # the old throttle: after each spawn, wait for every job once the pool is full
    perl -0pi.bak -e 's/    while \[ "\$\(live_count \$pids\)" -ge "\$JOBS" \]; do sleep 0.2; done\n    run_one "\$seed" &\n    pids="\$pids \$!"\n/    run_one "\$seed" &\n    running=\$((\${running:-0} + 1))\n    if [ "\$running" -ge "\$JOBS" ]; then wait; running=\$((running - 1)); fi\n/' "$T/tools/soak.sh"
    cmp -s "$T/tools/soak.sh" "$T/tools/soak.sh.bak" && { echo "FAIL: mutation did not apply"; exit 2; }
fi
cat > "$T/tools/headless.sh" <<'STUB'
#!/bin/sh
now() { perl -MTime::HiRes=time -e 'printf "%.6f\n", time'; }
echo "$(now) S" >> "$EVENTS"
sleep 2
echo "$(now) E" >> "$EVENTS"
exit 0
STUB
printf '#!/bin/sh\nexit 0\n' > "$T/incursion-headless"
chmod +x "$T/tools/soak.sh" "$T/tools/headless.sh" "$T/incursion-headless"
: > "$T/empty.keys"

export EVENTS="$T/events"
SOAK_JOBS=$JOBS SOAK_DIR="$T/out" "$T/tools/soak.sh" 8 1 "$T/empty.keys" > "$T/soak.log" 2>&1
lines="$(wc -l < "$T/out/exits" 2>/dev/null | tr -d ' ')"
lines="${lines:-0}"
# sweep: end sorts before start at an equal time, so touching sessions do not overlap
peak="$(sort -k1,1n -k2,2r "$T/events" | awk '$2=="S"{n++; if(e&&n>m)m=n} $2=="E"{n--; e=1} END{print m+0}')"

if [ "$peak" -ne "$JOBS" ] || [ "$lines" -ne 8 ]; then
    echo "FAIL: 8 sessions at SOAK_JOBS=$JOBS peaked at $peak alive at once after the first wave (need $JOBS), exits lines: $lines (need 8)"
    exit 1
fi
echo "PASS: 8 sessions at SOAK_JOBS=$JOBS peaked at $peak alive at once after the first wave, exits lines: $lines"
