#!/usr/bin/env bash
# gate: cheap
#
# inc-rwha: the load guard that finish_bead.sh runs once, before STEP 1. It
# must refuse an overloaded machine (exit 2, one line per tripped condition),
# pass a fit one (exit 0), and never wait or retry. Each condition is forced
# through a FAKE variable so no case needs to load the machine.
#
# Exit: 0 every case behaved
#       1 a case did not
#       2 could not measure
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$ROOT/tools/load_guard.sh"
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
expect "  and say nothing" clean

guard INCURSION_LOAD_GUARD_FAKE_LOAD=6.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=1 INCURSION_LOAD_GUARD_FAKE_GATES=0
expect "load 6.0 of 10 CPUs is refused" [ "$RC" = 2 ]
expect "  and names the load average" says "load average"

guard INCURSION_LOAD_GUARD_FAKE_LOAD=5.0 INCURSION_LOAD_GUARD_FAKE_NCPU=10 \
      INCURSION_LOAD_GUARD_FAKE_PRESSURE=1 INCURSION_LOAD_GUARD_FAKE_GATES=0
expect "load exactly at the limit passes" [ "$RC" = 0 ]
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
