#!/bin/bash
# Self-test of the TOO SLOW retry in tools/pressure/route.sh (inc-cjos0 phase 8, D4): a commit step whose output
# holds the fast set's exact message waits on the load guard and runs once more, both attempts recorded; any other
# failure is not retried. Stubs git, record and the guard; runs no build and touches no repository.
#   tools/pressure/selftest_retry.sh        exit 0 pass, 1 fail
# fact: the step output -- made up in this script; no game, no seed, no machine load
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/incursion-retry.XXXXXX")"; trap 'rm -rf "$T"' EXIT
LOG="$T"; CASE_NAME=x; FIRST_FAIL_LABEL=""; FIRST_FAIL_LOG=""
now() { echo 0; }
sha() { echo sha; }
wt() { echo "$T/w"; }
RECORDS=""; WAITS=0; COMMITS=0; MODE=slow
record() { RECORDS="$RECORDS|$1 rc=$3"; if [ "$3" -ne 0 ] && [ -z "$FIRST_FAIL_LABEL" ]; then FIRST_FAIL_LABEL="$1"; FIRST_FAIL_LOG="$2"; fi; }
git() { # git -C <w> apply|add|commit ...
    case "$3" in
        commit) COMMITS=$((COMMITS + 1))
                if [ "$MODE" = slow ] && [ $COMMITS -eq 1 ]; then echo "pre-commit: a fast check: TOO SLOW for the fast set (over 15 s)"; return 1; fi
                if [ "$MODE" = other ]; then echo "pre-commit: REFUSED: something else"; return 1; fi
                return 0;;
        *) return 0;;
    esac
}
# the functions under test, taken from route.sh itself
eval "$(sed -n '/^SLOW_MSG=/,/^}$/p' "$HERE/route.sh" | sed -n '/^SLOW_MSG=/p;/^slow_failed()/,/^}/p;/^wait_load_guard()/,/^}/p')"
eval "$(sed -n '/^patch_bead() {/,/^}/p' "$HERE/route.sh")"
wait_load_guard() { WAITS=$((WAITS + 1)); }
fail=0
chk() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1: got '$2', want '$3'"; fail=1; fi; }

patch_bead inc-x /dev/null; rc=$?
chk "a slow commit is retried and then passes" "$rc" 0
chk "one wait" "$WAITS" 1
chk "both attempts recorded" "$RECORDS" "|commit inc-x rc=1|commit inc-x (retry after TOO SLOW) rc=0"
chk "the passed retry clears the first failure" "$FIRST_FAIL_LABEL" ""

RECORDS=""; WAITS=0; COMMITS=0; MODE=other; FIRST_FAIL_LABEL=""
patch_bead inc-y /dev/null; rc=$?
chk "another failure is not retried" "$rc|$WAITS|$RECORDS" "1|0||commit inc-y rc=1"
exit $fail
