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

# inc-loa.3: give a session either shape of the death-prompt bug, the same way
# make_soak's errors.log lines stand in for a real run.
make_confirmed_death() { # <dir> <seed>
    mkdir -p "$1/seed-$2/logs"
    echo "=== character died 2026-08-16 00:00:00  turn 1  depth 1  xp 0 ===" \
        > "$1/seed-$2/logs/death.log"
}
make_stuck_death() { # <dir> <seed>
    mkdir -p "$1/seed-$2/logs/screens"
    printf '=== screen ===\nYou die... Die? [yn]\n' \
        > "$1/seed-$2/logs/screens/0001-final.txt"
}

# inc-loa.5: same idea, for the unguarded threat-disengage prompt. Only one
# shape exists for this one -- see tools/gate_lib.sh's comment on why there
# is no "confirmed" counterpart.
make_threat_frozen() { # <dir> <seed>
    mkdir -p "$1/seed-$2/logs/screens"
    printf '=== screen ===\nYou are in a threatened area. Abort, Flee or Disengage? [afd?]\n' \
        > "$1/seed-$2/logs/screens/0001-final.txt"
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

# 6. inc-loa.3: more sessions dying or getting stuck at the OPT_NODEATH
#    prompt than the baseline must fail, even though it can log LESS -- a
#    dead session generates no more real gameplay, so its errors and audit
#    findings undercount exactly like a genuinely quieter build would. This is
#    the same disease as the void check above (4), one prompt over: a build
#    that kills characters earlier must not read as a fix.
make_soak "$W/died" 0 "1:$QUIET" "2:$QUIET" "3:$QUIET"
make_confirmed_death "$W/died" 10
make_stuck_death "$W/died" 11
make_baseline "$W/died.baseline" "$W/died"
if ! grep -q '^died	2$' "$W/died.baseline"; then
    fail "gate_collect did not count one confirmed and one stuck death as 2"
fi

make_soak "$W/died-more" 0 "1:$QUIET" "2:$QUIET" "3:$QUIET"
make_confirmed_death "$W/died-more" 10
make_stuck_death "$W/died-more" 11
make_stuck_death "$W/died-more" 12
if ./tools/gate_compare.sh --from "$W/died-more" "$W/died.baseline" > "$W/out6a" 2>&1; then
    tail -20 "$W/out6a"
    fail "a run with more dead/stuck sessions than the baseline was reported as a pass"
elif ! grep -q "died or got stuck" "$W/out6a"; then
    fail "the extra dead/stuck sessions were not named as the reason for the fail"
fi

# The same run against itself must still pass -- this rule fires on an
# INCREASE, not on the mere presence of a death.
if ! ./tools/gate_compare.sh --from "$W/died" "$W/died.baseline" > "$W/out6b" 2>&1; then
    tail -20 "$W/out6b"
    fail "a run with the same dead/stuck count as its own baseline did not pass"
fi

# A baseline recorded before this fix existed has no 'died' field at all.
# That must not silently read as 0 -- a fresh run's real death count would
# then look like a regression every time, on baselines that said nothing
# false, they just never asked. It must warn and still pass.
grep -v '^died	' "$W/died.baseline" > "$W/died-old.baseline"
if ! ./tools/gate_compare.sh --from "$W/died" "$W/died-old.baseline" > "$W/out6c" 2>&1; then
    tail -20 "$W/out6c"
    fail "a baseline with no 'died' field failed the comparison instead of warning"
elif ! grep -q "predates death-counting" "$W/out6c"; then
    fail "a baseline with no 'died' field gave no warning about the missing count"
fi

# 6b. inc-loa.5: the same rule again, for the unguarded threat-disengage
#    prompt. A frozen session generates no more real gameplay either, so it
#    must not be allowed to read as a quieter, healthier build.
make_soak "$W/threat" 0 "1:$QUIET" "2:$QUIET" "3:$QUIET"
make_threat_frozen "$W/threat" 20
make_baseline "$W/threat.baseline" "$W/threat"
if ! grep -q '^threat_frozen	1$' "$W/threat.baseline"; then
    fail "gate_collect did not count one threat-disengage freeze"
fi

make_soak "$W/threat-more" 0 "1:$QUIET" "2:$QUIET" "3:$QUIET"
make_threat_frozen "$W/threat-more" 20
make_threat_frozen "$W/threat-more" 21
if ./tools/gate_compare.sh --from "$W/threat-more" "$W/threat.baseline" > "$W/out6d" 2>&1; then
    tail -20 "$W/out6d"
    fail "a run with more threat-frozen sessions than the baseline was reported as a pass"
elif ! grep -q "threat-disengage prompt" "$W/out6d"; then
    fail "the extra threat-frozen sessions were not named as the reason for the fail"
fi

if ! ./tools/gate_compare.sh --from "$W/threat" "$W/threat.baseline" > "$W/out6e" 2>&1; then
    tail -20 "$W/out6e"
    fail "a run with the same threat-frozen count as its own baseline did not pass"
fi

grep -v '^threat_frozen	' "$W/threat.baseline" > "$W/threat-old.baseline"
if ! ./tools/gate_compare.sh --from "$W/threat" "$W/threat-old.baseline" > "$W/out6f" 2>&1; then
    tail -20 "$W/out6f"
    fail "a baseline with no 'threat_frozen' field failed the comparison instead of warning"
elif ! grep -q "predates that count" "$W/out6f"; then
    fail "a baseline with no 'threat_frozen' field gave no warning about the missing count"
fi

# 7. The settings the run plays with are an input to the result, so a baseline
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
    echo "      map, reports a message that has gone as an improvement, fails"
    echo "      when more sessions die or get stuck at the death prompt or the"
    echo "      threat-disengage prompt than the baseline while warning rather"
    echo "      than guessing when a baseline never counted one at all, and"
    echo "      refuses to compare across two different sets of settings"
    exit 0
fi
exit 1
