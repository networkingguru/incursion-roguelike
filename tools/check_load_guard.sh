#!/usr/bin/env bash
# gate: cheap
#
# inc-rwha: the load guard that finish_bead.sh runs once, before STEP 1. It
# must refuse a machine under memory pressure (exit 2), pass any other (exit 0,
# whatever the load; inc-b0ziu.8 removed the load refusal), and never wait or
# retry. Each condition is forced
# through a FAKE variable so no case needs to load the machine.
#
# inc-p8bw: the pass path prints one ok line, and the bypass records a row in
# the load-guard log.
#
# fact: load average, cpu count, memory pressure -- the
#       INCURSION_LOAD_GUARD_FAKE_LOAD/_NCPU/_PRESSURE variables
# fact: the timing log location -- INCURSION_CHECK_TIMING_LOG=<temp file>
# fact: the bypass log location -- INCURSION_LOAD_GUARD_LOG=<temp file>
#
# Exit: 0 every case behaved
#       1 a case did not
#       2 could not measure
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# The guard under test. Overridable ONLY so the red/green proof can point this
# check at the pre-change script. Never set in normal use. inc-p8bw.
GUARD="${INCURSION_CHECK_LOAD_GUARD_UNDER_TEST:-$ROOT/tools/load_guard.sh}"
[ -x "$GUARD" ] || [ -r "$GUARD" ] || { echo "check_load_guard: no tools/load_guard.sh" >&2; exit 2; }

fails=0
OUT=""; RC=0

# guard <env assignments...> -> OUT, RC. The FAKE variables are cleared so a
# case only sets what it means to.
guard() {
    OUT=$(env -u INCURSION_LOAD_GUARD_OFF \
              -u INCURSION_LOAD_GUARD_FAKE_LOAD \
              -u INCURSION_LOAD_GUARD_FAKE_NCPU \
              -u INCURSION_LOAD_GUARD_FAKE_PRESSURE \
              -u INCURSION_LOAD_GUARD_LOG \
              "$@" "$GUARD" 2>&1)
    RC=$?
}
expect() { # expect <label> <command...>
    local label=$1; shift
    if "$@"; then
        printf 'ok    %s\n' "$label"
    else
        printf 'FAIL  %s\n' "$label"
        printf '%s\n' "$OUT" | sed 's/^/        /' | tail -8
        fails=$(( fails + 1 ))
    fi
}
says()  { grep -q -- "$1" <<< "$OUT"; }
clean() { ! grep -q 'REFUSED' <<< "$OUT"; }

idle() { guard INCURSION_LOAD_GUARD_FAKE_LOAD=1.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
               INCURSION_LOAD_GUARD_FAKE_PRESSURE=1; }

idle
expect "idle values pass" [ "$RC" = 0 ]
expect "  and print the ok line" bash -c 'grep -q "^load_guard: ok (" <<<"$1"' _ "$OUT"

guard INCURSION_LOAD_GUARD_FAKE_LOAD=10.5 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=1
expect "high load with calm pressure passes" [ "$RC" = 0 ]
expect "  prints the load line" says "load_guard: 1-min load 10.5, 10 CPUs (not a refusal)"
expect "  and says nothing refused" clean

guard INCURSION_LOAD_GUARD_FAKE_LOAD=1.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=2
expect "memory pressure 2 is refused" [ "$RC" = 2 ]
expect "  and names memory pressure" says "memory pressure"

# The guard no longer refuses for load or for another running gate (finish_bead.sh has a
# per-base-branch lock). Calm inputs must pass and never mention a gate.
idle
expect "calm inputs pass whatever gates run" [ "$RC" = 0 ]
expect "  and never mention a running gate" bash -c '! grep -q "gate is running" <<<"$1"' _ "$OUT"

guard INCURSION_LOAD_GUARD_OFF=1 INCURSION_LOAD_GUARD_FAKE_LOAD=9.0 \
      INCURSION_LOAD_GUARD_FAKE_NCPU=10 INCURSION_LOAD_GUARD_FAKE_PRESSURE=4
expect "the bypass overrides an overloaded machine" [ "$RC" = 0 ]
expect "  and announces the bypass" says "bypassed by INCURSION_LOAD_GUARD_OFF=1"

# inc-p8bw: the bypass must leave a record. Point the log at a temp file so the
# case writes nothing under the shared checkout.
LOG_TMP="$(mktemp "${TMPDIR:-/tmp}/load-guard-log.XXXXXX")" || { echo "check_load_guard: could not make a temp log" >&2; exit 2; }
: >"$LOG_TMP"
guard INCURSION_LOAD_GUARD_OFF=1 INCURSION_LOAD_GUARD_LOG="$LOG_TMP" \
      INCURSION_LOAD_GUARD_FAKE_LOAD=9.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=4
expect "the bypass still exits 0" [ "$RC" = 0 ]
expect "  and logs exactly one bypass row" \
    bash -c '[ "$(grep -c "bypass INCURSION_LOAD_GUARD_OFF=1 caller=load_guard.sh" "$1")" = 1 ]' _ "$LOG_TMP"
rm -f "$LOG_TMP"

# The timing-log helper writes the header on a new file, then exactly one
# 10-column row per call. inc-b0ziu.8.
TL="$(mktemp -u "${TMPDIR:-/tmp}/check-timing.XXXXXX")"
HELPER="${INCURSION_CHECK_TIMING_HELPER_UNDER_TEST:-$ROOT/tools/timing_log.sh}"
INCURSION_CHECK_TIMING_LOG="$TL" INCURSION_LOAD_GUARD_FAKE_LOAD=3.5 \
    INCURSION_LOAD_GUARD_FAKE_NCPU=10 INCURSION_LOAD_GUARD_FAKE_PRESSURE=1 \
    "$HELPER" fast check_x.sh 0 7 >/dev/null 2>&1
expect "the timing helper writes a header and one row" \
    bash -c '[ "$(awk "END{print NR}" "$1")" = 2 ] && [ "$(head -1 "$1" | cut -f1)" = utc_time ]' _ "$TL"
expect "  the header has 10 columns" \
    bash -c '[ "$(head -1 "$1" | awk -F"\t" "{print NF}")" = 10 ]' _ "$TL"
expect "  the row has 10 columns carrying the arguments and fakes" \
    bash -c 'r="$(sed -n 2p "$1")"; [ "$(printf "%s" "$r" | awk -F"\t" "{print NF}")" = 10 ] \
      && [ "$(printf "%s" "$r" | cut -f2,3,4,5,6,7,8)" = "$(printf "fast\tcheck_x.sh\t0\t7\t3.5\t10\t1")" ]' _ "$TL"
INCURSION_CHECK_TIMING_LOG="$TL" "$HELPER" gate check_y.sh 1 2 >/dev/null 2>&1
expect "a second call appends one row and no second header" \
    bash -c '[ "$(awk "END{print NR}" "$1")" = 3 ] && [ "$(grep -c "^utc_time" "$1")" = 1 ]' _ "$TL"
rm -f "$TL"
INCURSION_CHECK_TIMING_LOG=/nonexistent-dir/x/y/z.tsv "$HELPER" fast c 0 1 >/dev/null 2>&1
expect "the helper exits 0 even when it cannot write" [ "$?" = 0 ]

# No FAKE variables: the real sysctl paths run. Anything other than a
# clean 0 or 2 means the guard crashed or exited with a shell error.
guard
expect "the real measurement exits 0 or 2 only" test "$RC" = 0 -o "$RC" = 2

echo
if [ "$fails" = 0 ]; then
    echo "PASS: every case behaved"
    exit 0
fi
echo "FAIL: $fails case(s)"
exit 1
