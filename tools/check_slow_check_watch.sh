#!/bin/bash
# gate: cheap
# Does the gate alert once, with a CPU sample, when a check runs 5x past its
# expected time and past the floor -- and never change a check's exit code?
# (inc-omhv1: tools/slow_check_watch.py, hooked in nightly_verify.sh run_check.)
# `--selftest` reruns it with SLOW_WATCH_MUTATE=invert-threshold and requires red.
#
# fact: timing history -- fixed fake log in a temp dir, INCURSION_CHECK_TIMING_LOG; three 1 s gate rows for the slow and the fast fake check, none for the third
# fact: elapsed time of each fake check -- fixed sleeps in the fake scripts (10 s slow, 1 s fast, 7 s no-history) against a 5 s threshold, floor INCURSION_SLOW_WATCH_FLOOR=2
# fact: machine load -- INCURSION_LOAD_GUARD_FAKE_LOAD=7.25
# fact: branch name -- compared with git rev-parse --abbrev-ref HEAD of the same tree
# fact: alert file path -- INCURSION_FAST_ALERT_FILE in this check's temp dir; the sample files land beside it
# fact: the slow check's exit code -- fixed exit 3 in its fake script
# fact: number of gates running -- only printed in the alert, never matched
# (no seed, no game, no real log, no real alert file is touched)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = "--selftest" ]; then
    if SLOW_WATCH_MUTATE=invert-threshold "$0" > /dev/null 2>&1; then
        echo "FAIL: selftest -- the check stayed green with the threshold comparison broken"; exit 1
    fi
    "$0" > /dev/null 2>&1 || { echo "FAIL: selftest -- the check is red unmutated"; exit 1; }
    echo "ok: the check goes red when the threshold comparison is broken"; exit 0
fi

D="$(mktemp -d "${TMPDIR:-/tmp}/slowwatch.XXXXXX")" || exit 2
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/checks" "$D/out"
printf '#!/bin/sh\n# gate: cheap\nsleep 10\nexit 3\n' > "$D/checks/check_slowfake.sh"
printf '#!/bin/sh\n# gate: cheap\nsleep 1\nexit 0\n' > "$D/checks/check_fastfake.sh"
printf '#!/bin/sh\n# gate: cheap\nsleep 7\nexit 0\n' > "$D/checks/check_nohistfake.sh"
chmod +x "$D/checks"/*.sh

T="$D/timing.tsv"
printf 'utc_time\trunner\tcheck\texit\telapsed_s\tload1\tncpu\tmem_pressure\tgates_running\tbranch\n' > "$T"
for n in tools/check_slowfake.sh tools/check_fastfake.sh; do
    for _ in 1 2 3; do printf '2026-01-01T00:00:00Z\tgate\t%s\t0\t1\t1\t8\t1\t1\tb\n' "$n" >> "$T"; done
done

ALERT="$D/out/fast-alert.log"
INCURSION_CHECK_TIMING_LOG="$T" INCURSION_FAST_ALERT_FILE="$ALERT" INCURSION_SLOW_WATCH_FLOOR=2 \
    INCURSION_LOAD_GUARD_FAKE_LOAD=7.25 INCURSION_GATE_JOBS=4 \
    NIGHTLY_CHECK_DIR="$D/checks" NIGHTLY_VERIFY_STATE="$D/base.txt" \
    "$ROOT/tools/nightly_verify.sh" --checks-only > "$D/run.out" 2>&1

fails=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fails=1; }
lines() { grep -c "$1" "$ALERT" 2> /dev/null; }

[ "$(lines '^ALERT slow-check tools/check_slowfake.sh:')" = 1 ] && ok "one ALERT for the slow check" || bad "want exactly one ALERT for the slow check"
for pat in 'elapsed [0-9]*s' 'expected 1s (5x)' "branch $(git -C "$ROOT" rev-parse --abbrev-ref HEAD)" 'load 7.25' 'gates [0-9]' 'sample '; do
    grep -q -- "$pat" <<< "$(grep '^ALERT slow-check tools/check_slowfake.sh:' "$ALERT")" && ok "alert names: $pat" || bad "alert lacks: $pat"
done
[ "$(grep -c '^ALERT' "$ALERT" 2> /dev/null)" = 1 ] && ok "no other ALERT (fast and no-history checks silent)" || bad "want only the slow check's ALERT"
S="$(sed -n 's/^ALERT .* sample //p' "$ALERT" | head -1)"
if [ -n "$S" ] && [ -s "$S" ] && grep -q 'sleep' "$S"; then ok "sample is non-empty and names the slow process"; else bad "sample missing, empty or without the slow process: '$S'"; fi
[ "$(ls "$D/out"/slow-sample-* 2> /dev/null | wc -l | tr -d ' ')" = 1 ] && ok "exactly one sample file" || bad "want exactly one sample file"
grep -q '^=== exit 3$' "$D/nightly-verify/tools_check_slowfake.sh.log" 2> /dev/null && ok "the slow check's exit code 3 is unchanged" || bad "slow check exit code not 3 in its log"
grep -q '^=== exit 0$' "$D/nightly-verify/tools_check_nohistfake.sh.log" 2> /dev/null && ok "the no-history check kept exit 0" || bad "no-history check exit code changed"
[ "$fails" = 0 ] || { sed 's/^/  | /' "$D/run.out" | tail -30; ls "$D" "$D/out"; }
exit "$fails"
