#!/bin/bash
# Prove that the regression gate bites.
#
# The gate itself is checked against the real game by reintroducing a known
# defect, which costs a rebuild and two soaks. This checks the other half --
# that the comparison reaches the right verdict -- against made-up logs, in
# about a second. Both are needed: a comparison that always says PASS would
# survive the real test only until the day something actually breaks.
#
# Usage: tools/check_gate.sh   (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
. "$ROOT/tools/gate_lib.sh"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

W="$(mktemp -d "${TMPDIR:-/tmp}/incursion-gatecheck.XXXXXX")"
trap 'rm -rf "$W"' EXIT

SESSIONS=40

# Build a soak directory out of nothing. Arguments after the first two are
# "<seed>:<message>" pairs, one error line each.
make_soak() { # <dir> <how many sessions ended in NO GAMEPLAY> [seed:message ...]
    local dir="$1" void="$2" pair seed msg i
    shift 2
    mkdir -p "$dir"
    : > "$dir/exits"
    for i in $(seq 1 "$SESSIONS"); do
        if [ "$i" -le "$void" ]; then echo "$i 5" >> "$dir/exits"
        else echo "$i 0" >> "$dir/exits"; fi
    done
    for pair in "$@"; do
        seed="${pair%%:*}"
        msg="${pair#*:}"
        mkdir -p "$dir/seed-$seed/logs"
        echo "2026-08-15 12:00:00  $msg" >> "$dir/seed-$seed/logs/errors.log"
    done
}

# The baseline is written by the real collector, so this checks the format the
# gate actually reads rather than one invented here.
make_baseline() { # <file> <soakdir> [settings-checksum]
    {
        echo "# made by tools/check_gate.sh"
        printf 'keys\ttools/keys/dive.keys\n'
        printf 'first\t1\n'
        [ -n "${3:-}" ] && printf 'options\t%s\n' "$3"
        gate_collect "$2"
    } > "$1"
}

QUIET="the world is as expected"
NOISE="something that has never been seen before"

make_soak "$W/base" 0 "1:$QUIET" "2:$QUIET" "3:$QUIET"
make_baseline "$W/base.baseline" "$W/base"

# 1. The same run, compared with itself, must pass and must say nothing changed.
if ! ./tools/gate_compare.sh --from "$W/base" "$W/base.baseline" > "$W/out1" 2>&1; then
    tail -20 "$W/out1"
    fail "a run compared against its own baseline did not pass"
elif ! grep -q "no change" "$W/out1"; then
    fail "a run compared against its own baseline did not report 'no change'"
fi

# 2. A message the baseline never saw, in enough sessions to be real, must
#    fail. This is the whole purpose of the gate: it is the shape the Target
#    zero-init defect had, 89,545 assertions across almost every session.
make_soak "$W/bad" 0 "1:$QUIET" "2:$QUIET" "3:$QUIET" \
    "4:$NOISE" "5:$NOISE" "6:$NOISE" "7:$NOISE" "8:$NOISE"
if ./tools/gate_compare.sh --from "$W/bad" "$W/base.baseline" > "$W/out2" 2>&1; then
    tail -20 "$W/out2"
    fail "an unseen message in 5 of 40 sessions was reported as a pass"
fi

# 3. The same message in one session must NOT fail. The engine produces these
#    on its own: seed 3 logged an assertion in 2 runs out of 11 with no change
#    to the code at all. Failing on that would make the gate cry wolf.
make_soak "$W/flake" 0 "1:$QUIET" "2:$QUIET" "3:$QUIET" "4:$NOISE"
if ! ./tools/gate_compare.sh --from "$W/flake" "$W/base.baseline" > "$W/out3" 2>&1; then
    tail -20 "$W/out3"
    fail "an unseen message in 1 of 40 sessions was reported as a regression"
elif ! grep -q "fewer than" "$W/out3"; then
    fail "an unseen message in 1 session passed silently; it must still be printed"
fi

# 4. A build that stops reaching the map must fail, even though it logs less.
#    Every number in this report goes down when the run breaks, and without
#    this rule that reads as an improvement -- which is exactly how 250
#    sessions that played nothing became the evidence for a fix on 2026-08-14.
make_soak "$W/void" 9 "1:$QUIET"
if ./tools/gate_compare.sh --from "$W/void" "$W/base.baseline" > "$W/out4" 2>&1; then
    tail -20 "$W/out4"
    fail "a run where 9 of 40 sessions never reached a map was reported as a pass"
fi

# 5. A message that stops firing is a fix, not a failure.
make_soak "$W/fixed" 0 "1:$QUIET"
if ! ./tools/gate_compare.sh --from "$W/fixed" "$W/base.baseline" > "$W/out5" 2>&1; then
    tail -20 "$W/out5"
    fail "a run with fewer messages than the baseline was reported as a regression"
elif ! grep -q "quieter than the baseline" "$W/out5"; then
    fail "a run with fewer messages did not report the improvement"
fi

# 6. The settings the run plays with are an input to the result, so a baseline
#    recorded with different ones cannot be compared against. See inc-w43: the
#    finding count moved 4386 -> 4416 because Brian played mid-session and the
#    game rewrote Options.Dat. These check the rule that stops that, without
#    running the game.
echo "settings for the check" > "$W/opts"
SUM="$(gate_options_sum "$W/opts")"

make_baseline "$W/pinned.baseline" "$W/base" "$SUM"
if ! gate_options_check "$W/pinned.baseline" "$W/opts" > "$W/out6" 2>&1; then
    cat "$W/out6"
    fail "a baseline recorded with the very settings in use was refused"
fi

echo "somebody changed a setting" > "$W/opts2"
if gate_options_check "$W/pinned.baseline" "$W/opts2" > "$W/out7" 2>&1; then
    fail "a baseline recorded with DIFFERENT settings was accepted"
elif ! grep -q "not comparable" "$W/out7"; then
    fail "the settings mismatch was refused without saying why"
fi

if gate_options_check "$W/base.baseline" "$W/opts" > "$W/out8" 2>&1; then
    fail "a baseline with no settings checksum was accepted; every baseline"
    fail "recorded before the settings were pinned is that shape"
fi

if gate_options_check "$W/pinned.baseline" "$W/gone" > "$W/out9" 2>&1; then
    fail "a missing settings file was accepted"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: the gate fails on an unseen message in many sessions, tolerates"
    echo "      one in a single session, fails when sessions stop reaching the"
    echo "      map, reports a message that has gone as an improvement, and"
    echo "      refuses to compare across two different sets of settings"
    exit 0
fi
exit 1
