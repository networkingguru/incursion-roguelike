#!/usr/bin/env bash
# gate: cheap
#
# inc-rwha: the load guard that finish_bead.sh runs once, before STEP 1. It
# must refuse an overloaded machine (exit 2, one line per tripped condition),
# pass a fit one (exit 0), and never wait or retry. Each condition is forced
# through a FAKE variable so no case needs to load the machine.
#
# inc-p8bw: the pass path prints one ok line, and the bypass records a row in
# the load-guard log.
#
# fact: load average, cpu count, memory pressure, running gate -- the
#       INCURSION_LOAD_GUARD_FAKE_LOAD/_NCPU/_PRESSURE/_GATES variables
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
              -u INCURSION_LOAD_GUARD_FAKE_GATES \
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
               INCURSION_LOAD_GUARD_FAKE_PRESSURE=1 INCURSION_LOAD_GUARD_FAKE_GATES=0; }

idle
expect "idle values pass" [ "$RC" = 0 ]
expect "  and print the ok line" bash -c 'grep -q "^load_guard: ok (" <<<"$1"' _ "$OUT"

guard INCURSION_LOAD_GUARD_FAKE_LOAD=10.5 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=1 INCURSION_LOAD_GUARD_FAKE_GATES=0
expect "load above 10 CPUs is refused" [ "$RC" = 2 ]
expect "  and names the load average" says "load average"

guard INCURSION_LOAD_GUARD_FAKE_LOAD=10.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=1 INCURSION_LOAD_GUARD_FAKE_GATES=0
expect "load exactly at the limit passes" [ "$RC" = 0 ]
expect "  and says nothing" clean

# The old half-CPU limit (5 on 10 cores) refused 6.0; the whole-CPU limit
# passes it, so this case is what a restored n / 2 would fail.
guard INCURSION_LOAD_GUARD_FAKE_LOAD=6.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=1 INCURSION_LOAD_GUARD_FAKE_GATES=0
expect "load 6.0 of 10 CPUs now passes" [ "$RC" = 0 ]
expect "  and says nothing" clean

guard INCURSION_LOAD_GUARD_FAKE_LOAD=1.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=2 INCURSION_LOAD_GUARD_FAKE_GATES=0
expect "memory pressure 2 is refused" [ "$RC" = 2 ]
expect "  and names memory pressure" says "memory pressure"

guard INCURSION_LOAD_GUARD_FAKE_LOAD=1.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=1 INCURSION_LOAD_GUARD_FAKE_GATES=1
expect "another running gate is refused" [ "$RC" = 2 ]
expect "  and names the running gate" says "nightly_verify.sh"

guard INCURSION_LOAD_GUARD_OFF=1 INCURSION_LOAD_GUARD_FAKE_LOAD=9.0 \
      INCURSION_LOAD_GUARD_FAKE_NCPU=10 INCURSION_LOAD_GUARD_FAKE_PRESSURE=4 \
      INCURSION_LOAD_GUARD_FAKE_GATES=3
expect "the bypass overrides an overloaded machine" [ "$RC" = 0 ]
expect "  and announces the bypass" says "bypassed by INCURSION_LOAD_GUARD_OFF=1"

# inc-p8bw: the bypass must leave a record. Point the log at a temp file so the
# case writes nothing under the shared checkout.
LOG_TMP="$(mktemp "${TMPDIR:-/tmp}/load-guard-log.XXXXXX")" || { echo "check_load_guard: could not make a temp log" >&2; exit 2; }
: >"$LOG_TMP"
guard INCURSION_LOAD_GUARD_OFF=1 INCURSION_LOAD_GUARD_LOG="$LOG_TMP" \
      INCURSION_LOAD_GUARD_FAKE_LOAD=9.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=4 INCURSION_LOAD_GUARD_FAKE_GATES=3
expect "the bypass still exits 0" [ "$RC" = 0 ]
expect "  and logs exactly one bypass row" \
    bash -c '[ "$(grep -c "bypass INCURSION_LOAD_GUARD_OFF=1 caller=load_guard.sh" "$1")" = 1 ]' _ "$LOG_TMP"
rm -f "$LOG_TMP"

# No FAKE variables: the real sysctl and pgrep paths run. Anything other than a
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
