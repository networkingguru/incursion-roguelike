#!/bin/bash
# gate: live
# inc-6w5x: does a ranged shot that the line-of-fire code lands on a creature
# other than the aimed one carry the AIMED creature's illusion flag into
# Creature::Damage? It must not: the flag must describe the creature struck.
# Build: BACKEND=posix ./build_macos.sh
# Run: tools/check_ranged_illusion.sh
# Cases (probe INCURSION_RANGED_ILLUSION_PROBE=<mode>, log logs/ranged-illusion.log):
#   AIM-ILLUSION  aim at an illusion, shot strikes the real cover creature : MUST NOT crash, flag 0
#   AIM-REAL      aim at a real creature, shot strikes an illusion cover   : flag MUST be 1
#   CONTROL       aim at a real creature, strike it directly               : flag 0
#   LOC-ILLUSION  aim at a square holding an illusion, strike it directly  : flag MUST be 1
# INCURSION_LOF_FORCE_ROLL is not used: the probe forces the roll itself.
# A case with no DAMAGE line for the intended creature is UNMEASURED (exit 3), never PASS.
# Exit 0 only when every case passes; 1 on a failure; 3 when unmeasured.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs/runs
BASE="$(mktemp -d "$ROOT/logs/runs/ranged-illusion.XXXXXX")"
echo "Specimens: $BASE"
status=0

# run_case <name> <mode> <struck role> <expected flag>
run_case() {
    local name=$1 mode=$2 role=$3 want=$4
    local rd="$BASE/$name"
    mkdir -p "$rd"
    env INCURSION_BIN="$ROOT/incursion-headless" \
        INCURSION_RANGED_ILLUSION_PROBE=$mode INCURSION_RUN_DIR="$rd" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        tools/headless.sh tools/keys/ranged-illusion.keys 1 > "$rd.harness.txt" 2>&1
    local rc=$?
    local log="$rd/logs/ranged-illusion.log"
    local setup dmg asserts
    setup=$(grep -c '^SETUP ' "$log" 2>/dev/null)
    dmg=$(grep -c "^DAMAGE role=$role " "$log" 2>/dev/null)
    asserts=$(grep -c "ASSERT failed: 's' in file src/Creature.cpp" "$rd/logs/errors.log" 2>/dev/null)
    echo "  $name: harness-exit=$rc setup=${setup:-0} damage-on-$role=${dmg:-0} assert-s=${asserts:-0}"
    grep -h '^SETUP \|^DAMAGE \|^SHOT ' "$log" 2>/dev/null | sed 's/^/    /'
    if [ "${setup:-0}" -lt 1 ] || [ "${dmg:-0}" -lt 1 ]; then
        echo "UNMEASURED $name: the shot did not reach Damage on the $role creature; see $rd.harness.txt"
        [ "$status" -eq 0 ] && status=3
        return
    fi
    if [ "${asserts:-0}" -gt 0 ] || [ "$rc" -ge 128 ] || [ "$rc" -eq 7 ]; then
        echo "FAIL $name: crash or ASSERT after the hit (harness exit $rc, assert-s ${asserts:-0})"
        status=1; return
    fi
    if ! grep -q "^DAMAGE role=$role .* vicIllusionFlag=$want\$" "$log"; then
        echo "FAIL $name: vicIllusionFlag at Damage is not $want"
        status=1; return
    fi
    echo "PASS $name: struck the $role creature, flag $want"
}

run_case AIM-ILLUSION aim-illusion cover 0
run_case AIM-REAL aim-real cover 1
run_case CONTROL control target 0
run_case LOC-ILLUSION loc-illusion target 1
exit $status
