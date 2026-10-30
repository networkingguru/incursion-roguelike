#!/bin/bash
# gate: cheap
# gate-fast: static, python only, no build, under 1 s
# Does tools/gate_predict.py compute the gate's predicted time correctly?
#
# It writes a fixed fake timing log and fixed input lines, runs the predictor,
# and asserts exact numbers: the weighted mean, greedy list scheduling onto N
# slots, serial sums, the compare-mode background span, the tier-median
# fallback, partial=1, and --no-builds/--no-live. `--selftest` re-runs it with
# GATE_PREDICT_MUTATE=sum-parallel and requires it to go red.
#
# fact: timing history -- fixed fake log written to a temp dir, INCURSION_CHECK_TIMING_LOG
# fact: slot count -- --jobs argument in every call
# fact: gate order -- --mode argument in every call
# fact: input items -- fixed lines in this script
# (no seed, no game, no real log is read)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRED="$ROOT/tools/gate_predict.py"

if [ "${1:-}" = "--selftest" ]; then
    if GATE_PREDICT_MUTATE=sum-parallel "$0" > /dev/null 2>&1; then
        echo "FAIL: selftest -- the check stayed green with the scheduler broken"; exit 1
    fi
    "$0" > /dev/null 2>&1 || { echo "FAIL: selftest -- the check is red unmutated"; exit 1; }
    echo "ok: the check goes red when parallel scheduling is broken"; exit 0
fi

D="$(mktemp -d "${TMPDIR:-/tmp}/gatepred.XXXXXX")" || exit 2
trap 'rm -rf "$D"' EXIT
export INCURSION_CHECK_TIMING_LOG="$D/t.tsv"
row() { printf '2026-01-01T00:00:00Z\tgate\t%s\t%s\t%s\t1\t8\t1\t1\tb\n' "$1" "${3:-0}" "$2" >> "$INCURSION_CHECK_TIMING_LOG"; }
printf 'utc_time\trunner\tcheck\texit\telapsed_s\tload1\tncpu\tmem_pressure\tgates_running\tbranch\n' > "$INCURSION_CHECK_TIMING_LOG"
row W 10; row W 20 1; row W 30            # newest 30: (30+20*.87+10*.7569)/(1+.87+.7569)=20.83 -> 21
row A 10; row B 10; row C 10              # three 10 s cheap parallel checks
row S1 7; row S2 5                        # serial cheap
row BLD 100; row stage:build:1 100; row stage:build:2 50
row stage:tools/step.sh 40
row SM1 15; row SM2 15; row LV1 5; row LV2 5; row SMS 8; row LVS 9
row X 5; row Y 15; row Y 25; row Z 4; row Z notnum
printf '2026-01-01T00:00:00Z\tfast\tFASTROW\t0\t999\n' >> "$INCURSION_CHECK_TIMING_LOG"

fails=0
t() { # <name> <expected> <args...>  (stdin: input lines)
    local name="$1" want="$2" got; shift 2
    got="$("$PRED" "$@")"
    if [ "$got" = "$want" ]; then echo "ok: $name"; else echo "FAIL: $name -- want '$want' got '$got'"; fails=1; fi
}
T=$'\t'
t "weighted mean (21)" "predicted_s=21 checks=1 partial=0" --mode compare --jobs 2 <<<"check${T}W${T}cheap${T}0"
t "non-integer and fast rows ignored (Z=4)" "predicted_s=4 checks=1 partial=0" --mode compare --jobs 2 <<<"check${T}Z${T}cheap${T}0"
t "list scheduling 3x10 on 2 slots = 20" "predicted_s=20 checks=3 partial=0" --mode compare --jobs 2 <<<"check${T}A${T}cheap${T}0
check${T}B${T}cheap${T}0
check${T}C${T}cheap${T}0"
t "serial phase sums (12)" "predicted_s=12 checks=2 partial=0" --mode compare --jobs 2 <<<"check${T}S1${T}cheap${T}1
check${T}S2${T}cheap${T}1"
ALL="check${T}S1${T}cheap${T}1
build${T}stage:build:1${T}${T}
build${T}stage:build:2${T}${T}
step${T}stage:tools/step.sh${T}${T}
check${T}SM1${T}smoke${T}0
check${T}SM2${T}smoke${T}0
check${T}LV1${T}live${T}0
check${T}LV2${T}live${T}0
check${T}SMS${T}smoke${T}1
check${T}LVS${T}live${T}1"
# compare: S1 7 + builds 150 + max(step 40, smoke par 15 + live par 5 = 20) + 8 + 9 = 214
t "compare: span = max(step 40, 20)" "predicted_s=214 checks=7 partial=0" --mode compare --jobs 2 <<<"$ALL"
# record: builds 150 + cheap serial 7 + smoke par 15 + smoke ser 8 + live par 5 + live ser 9 + steps 40 = 234
t "record: steps summed at the end" "predicted_s=234 checks=7 partial=0" --mode record --jobs 2 <<<"$ALL"
# no step in the input: span = smoke par 15 + live par 5 = 20 -> 7 + 150 + 20 + 8 + 9 = 194
t "compare: smoke+live wins without a step" "predicted_s=194 checks=7 partial=0" --mode compare --jobs 2 <<<"$(grep -v stage:tools/step.sh <<<"$ALL")"
# no builds, no live: only S1 (7) + SM1,SM2 dropped (smoke) -> 7
t "--no-builds --no-live drops phases" "predicted_s=7 checks=1 partial=0" --mode compare --jobs 2 --no-builds --no-live <<<"$ALL"
# no builds only: 7 + span max(0, 20) + 8 + 9 = 44
t "--no-builds drops builds and steps" "predicted_s=44 checks=7 partial=0" --mode compare --jobs 2 --no-builds <<<"$ALL"
# NEW has no history: cheap tier median of A,B,C = 10 -> three 10s on 2 slots plus NEW 10 = 20
t "tier-median fallback (10)" "predicted_s=20 checks=4 partial=0" --mode compare --jobs 2 <<<"check${T}A${T}cheap${T}0
check${T}B${T}cheap${T}0
check${T}C${T}cheap${T}0
check${T}NEW${T}cheap${T}0"
# NEW (cheap) has no history and no cheap peer: all-tier median of LV1 = 5; cheap 5 + live 5 = 10
t "all-tier median fallback (5)" "predicted_s=10 checks=2 partial=0" --mode compare --jobs 2 <<<"check${T}NEW${T}cheap${T}0
check${T}LV1${T}live${T}0"
t "nothing has history -> partial" "predicted_s=0 checks=1 partial=1" --mode compare --jobs 2 <<<"check${T}NOPE${T}cheap${T}0"
t "step without history -> partial" "predicted_s=0 checks=0 partial=1" --mode compare --jobs 2 <<<"step${T}stage:none${T}${T}"
exit "$fails"
