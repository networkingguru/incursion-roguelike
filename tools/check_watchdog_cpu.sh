#!/bin/bash
# gate: none plays the game under CPU contention and needs the headless build, about 30 s
# Does the headless watchdog count CPU time, not wall time? (bd inc-sbx6t)
#
# DEFECT. The watchdog ended a session when 300 s of WALL time passed between
# two key reads. On a loaded machine a healthy session was ended and reported
# "WATCHDOG -- the game stopped asking for keystrokes". It now counts the
# process's own CPU time (setitimer ITIMER_PROF), so other processes cannot
# trip it, and a loop between key reads still does.
#
# fact: character -- fixture lizardfolk-monk-seed1 (INCURSION_LOAD)
# fact: settings -- tools/fixtures/options-2026-08-22.dat (INCURSION_OPTIONS)
# fact: random stream -- the verdict reads only the exit status, never a roll; seed 1 is pinned and no assertion depends on it (bead inc-sbx6t)
# fact: watchdog limit -- INCURSION_WATCHDOG_S=1 (CPU seconds)
# fact: a game that stops asking for keys -- INCURSION_WATCHDOG_PROBE=3 (spin from the third key read)
# fact: machine load -- this check starts and stops its own busy processes
#
# (a) With the probe and a 2 s limit the session ends WATCHDOG (exit 4).
# (b) Unloaded, the session with a 1 s limit does not end WATCHDOG. Then it is
#     run again beside 4 busy processes per CPU. The startup gap alone takes
#     longer than 1 s of wall time there, and the session must end the same way.
#
# Usage: tools/check_watchdog_cpu.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=lizardfolk-monk-seed1
KEYS=tools/keys/load-char-sheet.keys
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wdcpu.XXXXXX")"
PIDS=()
cleanup() {
    if [ "${#PIDS[@]}" -gt 0 ]; then { kill "${PIDS[@]}"; wait "${PIDS[@]}"; } 2>/dev/null; fi
    rm -rf "$TMP"
}
trap cleanup EXIT

FAIL=0
verdict() { # verdict <name> <extra env...> ; prints the headless.sh ended line
    local name="$1"; shift
    env "$@" INCURSION_RUN_DIR="$TMP/$name" tools/headless.sh "$KEYS" 1 2>&1 | grep '^ended:'
}
expect() { # expect <label> <got> <want-regex>
    if grep -q "$3" <<< "$2"; then echo "  ok    $1"
    else echo "  FAIL  $1: got '$2'"; FAIL=1; fi
}

if [ ! -x ./incursion-headless ]; then
    echo "FAIL: ./incursion-headless is missing; run BACKEND=posix ./build_macos.sh"; exit 2
fi

A="$(verdict a INCURSION_WATCHDOG_S=2 INCURSION_WATCHDOG_PROBE=3)"
expect "(a) a game that spins between key reads ends WATCHDOG" "$A" "WATCHDOG"

U="$(verdict unloaded INCURSION_WATCHDOG_S=1)"
expect "(b) unloaded, a 1 s CPU limit does not end the session" "$U" "cleanly"

NCPU="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
for _ in $(seq 1 $((NCPU * 4))); do
    yes >/dev/null & PIDS+=("$!")
done
L="$(verdict loaded INCURSION_WATCHDOG_S=1)"
{ kill "${PIDS[@]}"; wait "${PIDS[@]}"; } 2>/dev/null
PIDS=()
expect "(b) under CPU contention the session ends the same way" "$L" "cleanly"

if [ "$FAIL" -eq 0 ]; then echo "PASS: check_watchdog_cpu.sh"; else echo "FAIL: check_watchdog_cpu.sh"; fi
exit "$FAIL"
