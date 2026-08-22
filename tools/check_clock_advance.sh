#!/bin/bash
# Regression check for the game-time oracle in tools/headless.sh (inc-2k3).
#
# WHAT IT PROTECTS, AND WHY IT EXISTS
#
# A scripted session can read every keystroke it has and play nothing. It
# happens whenever the game enters a screen the key script cannot leave: the
# death prompt (inc-loa.3), the threat-disengage prompt (inc-loa.5), Inventory
# Mode, or a command the game simply refuses (inc-loa.2). The run still exits
# 0, still writes a full set of screen dumps, and still reports "ended:
# cleanly". Every earlier defence against this matched one prompt's literal
# text, so each new trap needed a new detector and was found only after it had
# wasted a soak.
#
# All of them share one signature: keys are consumed and no game time passes.
# posixTerm::DumpScreen stamps theGame->Turn into each dump header, and
# headless.sh turns consecutive stamps into a "game time:" report. This check
# protects that chain end to end.
#
# THE MEASUREMENT THAT MADE IT NECESSARY. tools/keys/marathon.keys exists only
# to reproduce inc-2k3, Brian's report that the game slows the longer it runs.
# On seed 7 it spent 6,059 of its 10,621 keys parked in Inventory Mode with
# the turn counter frozen at 349,157, and the harness called the session
# clean. The instrument built to measure the bug was measuring nothing, and
# there was no way to see it.
#
# Usage: tools/check_clock_advance.sh              (exits 0 on pass, 1 on fail)
#        tools/check_clock_advance.sh --selftest   (proves the assertions bite)
#        tools/check_clock_advance.sh --live [seed]  (also runs a real session)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SELFTEST=0
LIVE=0
[ "${1:-}" = "--selftest" ] && SELFTEST=1 && shift
[ "${1:-}" = "--live" ] && LIVE=1 && shift
SEED="${1:-7}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILED=1; }

# Build a fake run directory whose screen dumps carry the given "key:turn"
# pairs, then ask headless.sh's reporter what it makes of them. Fabricating
# the dumps rather than playing a game keeps this check deterministic and
# fast; the --live mode below covers the other half, that a real binary
# actually writes the stamp.
_fake_run() { # <dir> <key:turn>...
    local d="$1"; shift
    local n=0 pair k t
    mkdir -p "$d/logs/screens"
    for pair in "$@"; do
        n=$((n + 1))
        k="${pair%%:*}"; t="${pair##*:}"
        printf '=== screen %04d fake  key %s  mode 2  turn %s ===\nYou walk on.\n' \
            "$n" "$k" "$t" > "$(printf '%s/logs/screens/%04d-fake.txt' "$d" "$n")"
    done
}

# Grade a fabricated run with the SAME awk program headless.sh ships, so this
# check cannot pass against a copy that has drifted from the shipped text.
_report() { # <dir> -> the "game time:" lines
    local d="$1"
    for f in $(ls "$d/logs/screens"/*.txt 2>/dev/null | sort); do
        sed -n '1s/.*key \([0-9]*\).*turn \([0-9]*\).*/\1 \2/p' "$f"
    done | awk -f "$ROOT/tools/gametime.awk"
}

echo "1. a healthy session reports no stall"
_fake_run "$WORK/ok" 100:1000 200:1500 300:2200 400:3000
OUT="$(_report "$WORK/ok")"
echo "$OUT" | grep -q 'No stall' && pass "clean run is clean" || fail "clean run flagged: $OUT"
echo "$OUT" | grep -q 'ZERO turns' && fail "clean run reported frozen intervals" || pass "no frozen intervals claimed"

echo "2. a session that freezes at the end is reported STALLED"
_fake_run "$WORK/stall" 100:1000 200:1500 300:1500 400:1500
OUT="$(_report "$WORK/stall")"
echo "$OUT" | grep -q 'STALLED' && pass "trailing freeze caught" || fail "trailing freeze missed: $OUT"
echo "$OUT" | grep -q 'last 200 keys (from key 200)' && pass "reports the right key span" ||
    fail "wrong key span: $OUT"

echo "3. a freeze in the middle is counted but is not a stall"
_fake_run "$WORK/mid" 100:1000 200:1000 300:1800 400:2600
OUT="$(_report "$WORK/mid")"
echo "$OUT" | grep -q 'STALLED' && fail "mid-run pause wrongly called a stall: $OUT" ||
    pass "mid-run pause is not a stall"
echo "$OUT" | grep -q '1 of 3 intervals advanced ZERO turns' && pass "mid-run pause counted" ||
    fail "mid-run pause not counted: $OUT"

echo "4. the turn stamp is present in the shipped dump header"
grep -q 'turn %u ===' src/Wposix.cpp &&
    pass "src/Wposix.cpp still writes the turn field" ||
    fail "src/Wposix.cpp no longer writes 'turn %u' -- the oracle has no input"

echo "5. headless.sh still feeds the shared reporter"
grep -q 'awk -f tools/gametime.awk' tools/headless.sh &&
    pass "headless.sh calls tools/gametime.awk" ||
    fail "headless.sh no longer calls tools/gametime.awk -- this check now grades nothing that ships"

if [ "$SELFTEST" -eq 1 ]; then
    echo "6. selftest: the assertions bite when fed known-bad input"
    _fake_run "$WORK/bad" 100:1000 200:1000 300:1000
    OUT="$(_report "$WORK/bad")"
    echo "$OUT" | grep -q 'STALLED' && pass "an all-frozen run is caught" ||
        fail "an all-frozen run was NOT caught -- this check tests nothing"
    # A dump with no turn field must say so. The dangerous answer is not an
    # error, it is silence that a caller reads as "no stall found".
    mkdir -p "$WORK/notstamped/logs/screens"
    printf '=== screen 0001 old  key 10  mode 2 ===\n' \
        > "$WORK/notstamped/logs/screens/0001-old.txt"
    OUT="$(_report "$WORK/notstamped")"
    echo "$OUT" | grep -q 'no screen dump carried a turn stamp' &&
        pass "an unstamped dump is reported as ungradeable" ||
        fail "an unstamped dump was not reported as ungradeable: $OUT"
    echo "$OUT" | grep -q 'No stall' &&
        fail "an unstamped dump was passed as clean -- silence read as success" ||
        pass "an unstamped dump is never passed as clean"
fi

if [ "$LIVE" -eq 1 ]; then
    echo "7. live: a real session stamps a real turn counter"
    OUT="$(tools/headless.sh tools/keys/smoke.keys "$SEED" 2>&1)"
    echo "$OUT" | grep -q 'game time:  [0-9]* turns' &&
        pass "a real run reported real game time" ||
        fail "a real run reported no game time: $(echo "$OUT" | grep 'game time' || echo none)"
    echo "$OUT" | grep -q 'game time:  unknown' &&
        fail "the binary is not writing the turn stamp -- rebuild it" ||
        pass "the binary writes the turn stamp"
fi

echo
if [ "$FAILED" -eq 0 ]; then
    echo "check_clock_advance: PASS"
else
    echo "check_clock_advance: FAIL"
fi
exit "$FAILED"
