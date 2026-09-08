#!/usr/bin/env bash
#
# Does this build still play the same game when its objects move? (inc-dhc)
#
#   tools/check_layout_sweep.sh              build the probe, then sweep
#   tools/check_layout_sweep.sh --no-build   sweep with the incursion-probe here
#   tools/check_layout_sweep.sh --selftest   prove this script still bites
#
# Exit: 0 every seed that was measured played the same game in both layouts
#       1 at least one did NOT -- this build reads a memory address as data
#       2 nothing was measured, and the reason is printed
#
# WHAT THIS IS FOR. inc-dhc is a class, not one bug: the engine compares two
# heap addresses somewhere, the allocator puts objects in a different place on
# every launch, and so the same seed plays a different game. Two sites were
# found and fixed -- 2f0100b, a monster's target list sorted by memory position,
# and 949f73b, a fall charged to whichever creature three globals still named.
# tools/check_layout.sh is the experiment that decides ONE seed. This runs it
# across many seeds and many key scripts, because that is the only way the class
# is ever closed: a passing seed says only that THAT seed, on THAT script,
# reached no site that reads an address.
#
# WHY IT IS NOT IN THE RATCHET. nightly_verify.sh's ratchet promises checks that
# cost seconds and need no build. This one builds the DIVERGE_PROBE binary and
# then runs four headless sessions per seed under lldb. It belongs beside
# check_linux_build.sh, with the builds, for exactly the same reason.
#
# WHY A SKIP IS NOT A FAILURE. No lldb, no probe build, or a seed whose sessions
# never reached gameplay: none of those says the tree is broken. They say nothing
# was measured, and nothing is not a failure. A sweep that measured NOTHING is
# not a pass either, so that case is exit 2.
#
# READ THE COVERAGE LINE, NOT ONLY THE VERDICT. The key scripts differ enormously
# in how much game they actually buy, and only the long ones test a long session,
# which is where inc-dhc's own symptom appeared. Measured 2026-09-08 over seeds
# 1-12: explore.keys buys 34,701 to 39,430 turns and stalls only on its last two
# keys; marathon.keys buys 8,703 to 10,890 and then stalls; dive.keys buys 198 to
# 6,714 and stalls after about key 219 (inc-loa.2, inc-upw.44); dive12.keys tracks
# dive.keys seed for seed, being a prefix of it. So keep at least one long script
# in the set. A seed whose session bought less than LAYOUT_SWEEP_MIN_TURNS of game
# time is counted as unmeasured rather than as a pass, because a green tick on a
# session that never played is the false agreement this whole instrument exists to
# avoid. A FAIL is always believed, however short the session: it found a real
# divergence.
#
# Env: LAYOUT_SWEEP_SEEDS      seeds to try          (default 1..6)
#      LAYOUT_SWEEP_KEYS       key scripts to try    (default three below)
#      LAYOUT_SWEEP_MIN_TURNS  the coverage floor    (default 100)
#      LAYOUT_SWEEP_DIR        where to keep screens (default logs/layout-sweep/)
#      LAYOUT_BIN              the probe binary      (default ./incursion-probe)
#      LAYOUT_CHECK            the per-seed experiment (default check_layout.sh);
#                              --selftest points it at a stub, and nothing else
#                              should ever set it.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BUILD=1
SELFTEST=0
case "${1:-}" in
    --no-build)  BUILD=0 ;;
    --selftest)  SELFTEST=1; BUILD=0 ;;
    "")          ;;
    -h|--help)   sed -n '2,11p' "$0"; exit 0 ;;
    *)           echo "unknown argument: $1" >&2; exit 2 ;;
esac

SEEDS="${LAYOUT_SWEEP_SEEDS:-1 2 3 4 5 6}"
# Three scripts and six seeds: 18 seed-runs, measured at 3m37s including the
# probe build on 2026-09-08, against about ten minutes for the Linux build beside
# it. Six seeds is an alarm, not a hunt -- a newly written site is reached by many
# seeds, and a hunt widens LAYOUT_SWEEP_SEEDS by hand. dive12.keys is deliberately
# absent: it is a prefix of dive.keys and its turn counts track it seed for seed,
# so it buys coverage nobody needs twice.
KEYSCRIPTS="${LAYOUT_SWEEP_KEYS:-tools/keys/dive.keys tools/keys/explore.keys tools/keys/marathon.keys}"
MIN_TURNS="${LAYOUT_SWEEP_MIN_TURNS:-100}"
BIN="${LAYOUT_BIN:-./incursion-probe}"
CHECK="${LAYOUT_CHECK:-tools/check_layout.sh}"

# lldb is the default experiment's requirement, not this script's, so the probe
# is skipped when --selftest has swapped the experiment for a stub.
if [ "$CHECK" = "tools/check_layout.sh" ]; then
    command -v lldb > /dev/null || {
        echo "COULD NOT MEASURE: lldb not found. It is what switches address"
        echo "  randomisation off, without which the two layouts differ by more"
        echo "  than this asks for. See tools/check_layout.sh."
        exit 2
    }
fi

# ---- selftest ------------------------------------------------------------
# Three stub experiments, one per verdict this script can reach. It exists
# because the real experiment passes on every seed today, so nothing else in
# the tree would notice if the FAIL path or the coverage floor stopped working.
if [ "$SELFTEST" = 1 ]; then
    tmp="$(mktemp -d)" || exit 2
    trap 'rm -rf "$tmp"' EXIT
    st=0

    stub() { # stub <name> <turns> <exit code>
        cat > "$tmp/$1" <<STUB
#!/usr/bin/env bash
mkdir -p "\$LAYOUT_DIR"
echo "game time:  $2 turns over 900 keys (0.5 turns/key)" > "\$LAYOUT_DIR/a1.out"
exit $3
STUB
        chmod +x "$tmp/$1"
    }

    expect() { # expect <name> <stub> <wanted exit>
        LAYOUT_CHECK="$tmp/$2" LAYOUT_BIN=/bin/echo \
        LAYOUT_SWEEP_SEEDS=1 LAYOUT_SWEEP_KEYS=tools/keys/smoke.keys \
        LAYOUT_SWEEP_DIR="$tmp/work-$2" \
            "$0" --no-build > "$tmp/$2.log" 2>&1
        local got=$?
        if [ "$got" != "$3" ]; then
            echo "SELFTEST FAIL: $1 exited $got, wanted $3 (see $tmp/$2.log)"
            cat "$tmp/$2.log"
            st=1
        fi
    }

    stub deep.sh    500 0
    stub shallow.sh   5 0
    stub diverge.sh 500 1

    expect "a seed that played and agreed"      deep.sh    0
    expect "a seed too shallow to be evidence"  shallow.sh 2
    expect "a seed that diverged"               diverge.sh 1

    [ "$st" -eq 0 ] && echo "SELFTEST PASS: check_layout_sweep.sh sees all three verdicts"
    exit "$st"
fi

if [ "$BUILD" = 1 ]; then
    printf 'building %s ... ' "$BIN"
    if EXTRA_CXXFLAGS=-DDIVERGE_PROBE OUT="$(basename "$BIN")" BACKEND=posix \
            ./build_macos.sh > /dev/null 2>&1; then
        echo "ok"
    else
        echo "FAILED"
        echo "COULD NOT MEASURE: the probe build did not compile. Re-run it to see why:"
        echo "  EXTRA_CXXFLAGS=-DDIVERGE_PROBE OUT=$(basename "$BIN") BACKEND=posix ./build_macos.sh"
        exit 2
    fi
elif [ ! -x "$BIN" ]; then
    echo "COULD NOT MEASURE: $BIN is not built, and --no-build was given."
    exit 2
fi

WORK="${LAYOUT_SWEEP_DIR:-$ROOT/logs/layout-sweep/$(date +%Y%m%d-%H%M%S)-$$}"
mkdir -p "$WORK" || exit 2

echo "seeds:    $SEEDS"
echo "scripts:  $KEYSCRIPTS"
echo "floor:    $MIN_TURNS turns of game time before a pass counts"
echo "into:     $WORK"
echo

PASSED=0
FAILED=0
SHALLOW=0
UNMEASURED=0
LOWEST=""
HIGHEST=""
FAIL_LINES=""

# The turn count the harness prints after a session. It is the honest measure of
# how much game a seed actually bought; the key count is not, because a stalled
# session keeps consuming keys while the clock stands still.
# The count is read with an anchored substitution and not a bare grep, because
# the harness line ends "... (0.26 turns/key)" and a loose '[0-9]+ turns' match
# picks that up as a second number. The selftest caught exactly that.
turns_of() { # turns_of <run dir> -> one number, or nothing
    sed -n 's/.*game time:[[:space:]]*\([0-9][0-9]*\) turns.*/\1/p' \
        "$1/a1.out" 2>/dev/null | head -1
}

for keys in $KEYSCRIPTS; do
    if [ ! -f "$keys" ]; then
        echo "no such key script, skipped: $keys"
        continue
    fi
    tag="$(basename "$keys" .keys)"
    for seed in $SEEDS; do
        dir="$WORK/$tag-seed$seed"
        LAYOUT_DIR="$dir" LAYOUT_BIN="$BIN" \
            "$CHECK" "$seed" "$keys" > "$WORK/$tag-seed$seed.out" 2>&1
        rc=$?
        turns="$(turns_of "$dir")"
        [ -n "$turns" ] || turns=0

        case "$rc" in
        1)  # Believed whatever the session length: a divergence is a divergence.
            printf 'FAIL    %-8s seed %-3s %s turns\n' "$tag" "$seed" "$turns"
            FAILED=$((FAILED + 1))
            FAIL_LINES="$FAIL_LINES  $CHECK $seed $keys"$'\n'
            ;;
        0)  if [ "$turns" -lt "$MIN_TURNS" ]; then
                printf 'shallow %-8s seed %-3s %s turns -- under the floor, not counted\n' \
                    "$tag" "$seed" "$turns"
                SHALLOW=$((SHALLOW + 1))
            else
                printf 'ok      %-8s seed %-3s %s turns\n' "$tag" "$seed" "$turns"
                PASSED=$((PASSED + 1))
                if [ -z "$LOWEST" ] || [ "$turns" -lt "$LOWEST" ]; then
                    LOWEST="$turns"
                fi
                if [ -z "$HIGHEST" ] || [ "$turns" -gt "$HIGHEST" ]; then
                    HIGHEST="$turns"
                fi
            fi
            ;;
        *)  printf 'skip    %-8s seed %-3s (could not measure)\n' "$tag" "$seed"
            UNMEASURED=$((UNMEASURED + 1))
            ;;
        esac
    done
done

echo
echo "measured $PASSED, diverged $FAILED, too shallow to count $SHALLOW, unmeasured $UNMEASURED"
if [ "$PASSED" -gt 0 ]; then
    echo "coverage: the counted seeds bought $LOWEST to $HIGHEST turns of game time."
    echo "          The low end is dive.keys, which stalls early (inc-loa.2). The"
    echo "          long sessions are the explore.keys rows; read those before"
    echo "          believing this build is clear of the class."
fi

if [ "$FAILED" -gt 0 ]; then
    echo
    echo "=== FAIL: this build plays a different game when its objects move. ==="
    echo "Reproduce one of them, and read the first differing PROBE line:"
    printf '%s' "$FAIL_LINES"
    echo "Screens and probe traces are in $WORK"
    exit 1
fi

if [ "$PASSED" -eq 0 ]; then
    echo
    echo "=== COULD NOT MEASURE: no seed played enough game to be evidence. ==="
    echo "Output per seed is in $WORK"
    exit 2
fi

echo
echo "=== PASS: no measured seed read a memory address as data. ==="
exit 0
