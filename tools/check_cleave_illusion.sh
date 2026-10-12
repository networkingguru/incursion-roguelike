#!/bin/bash
# gate: live
# inc-k0e1: does Cleave from a killed illusion crash Damage (getIllusionFlags
# ASSERT 's', then null dereference)? It must not.
# Build: BACKEND=posix ./build_macos.sh
# Run: tools/check_cleave_illusion.sh
# Cases (probe INCURSION_CLEAVE_ILLUSION_PROBE=<mode>, log logs/cleave-illusion.log):
#   ILLUSION first victim an illusion at 1 HP, real bugbear beside : MUST NOT crash
#   CONTROL  first victim real at 1 HP, real bugbear beside        : MUST NOT crash
# INCURSION_LOF_FORCE_ROLL=20 (existing hook, Fight.cpp) makes every attack roll hit.
# A case where no CLEAVE line is logged is UNMEASURED (exit 3), never PASS.
# Exit 0 only when every case passes; 1 on a crash; 3 when unmeasured.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs/runs
BASE="$(mktemp -d "$ROOT/logs/runs/cleave-illusion.XXXXXX")"
echo "Specimens: $BASE"
status=0

# run_case <name> <mode illusion|real>
run_case() {
    local name=$1 mode=$2
    local rd="$BASE/$name"
    mkdir -p "$rd"
    env INCURSION_BIN="$ROOT/incursion-headless" \
        INCURSION_CLEAVE_ILLUSION_PROBE=$mode INCURSION_LOF_FORCE_ROLL=20 \
        INCURSION_RUN_DIR="$rd" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        tools/headless.sh tools/keys/cleave-illusion.keys 1 > "$rd.harness.txt" 2>&1
    local rc=$?
    local log="$rd/logs/cleave-illusion.log"
    local setup cleave
    setup=$(grep -c '^SETUP ' "$log" 2>/dev/null)
    cleave=$(grep -c '^CLEAVE ' "$log" 2>/dev/null)
    local asserts
    asserts=$(grep -c "ASSERT failed: 's' in file src/Creature.cpp" "$rd/logs/errors.log" 2>/dev/null)
    echo "  $name: harness-exit=$rc setup=${setup:-0} cleave=${cleave:-0} assert-s=${asserts:-0}"
    grep -h '^SETUP \|^DAMAGE \|^CLEAVE ' "$log" 2>/dev/null | sed 's/^/    /'
    if [ "${asserts:-0}" -gt 0 ] || [ "$rc" -ge 128 ] || [ "$rc" -eq 7 ]; then
        echo "FAIL $name: crash or ASSERT (harness exit $rc, assert-s ${asserts:-0})"
        status=1; return
    fi
    if [ "${setup:-0}" -lt 1 ] || [ "${cleave:-0}" -lt 1 ]; then
        echo "UNMEASURED $name: no Cleave fired (setup=${setup:-0} cleave=${cleave:-0}); see $rd.harness.txt"
        [ "$status" -eq 0 ] && status=3
        return
    fi
    echo "PASS $name: Cleave fired, no crash"
}

run_case ILLUSION illusion
run_case CONTROL real
exit $status
