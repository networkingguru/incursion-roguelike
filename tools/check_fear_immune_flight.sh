#!/bin/bash
# gate: live
# inc-c36o: does a fear-immune monster below 1/3 hit points run the low-HP
# flee branch (Monster.cpp ChooseAction)? It must not.
# Build: BACKEND=posix ./build_macos.sh
# Run: tools/check_fear_immune_flight.sh
# Cases (probe INCURSION_LOWHP_FEAR_PROBE=$mon, log logs/lowhp-fear.log):
#   IMMUNE  blackguard goblin pinned at 1/4 HP : MUST NOT reach the flee branch
#   CONTROL plain bugbear pinned at 1/4 HP      : MUST reach the flee branch
#   HEALTHY blackguard goblin at full HP       : MUST NOT reach the flee branch
# Exit 0 only when every case passes.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs/runs
BASE="$(mktemp -d "$ROOT/logs/runs/fear-immune-flight.XXXXXX")"
echo "Specimens: $BASE"
status=0

# run_case <name> <keys> <pin 0|1> <want-flee 0|1> <immune 0|1> [monster]
run_case() {
    local mon=${6:-goblin}
    local name=$1 keys=$2 pin=$3 want=$4 immune=$5
    local rd="$BASE/$name"
    mkdir -p "$rd"
    local pinenv=()
    [ "$pin" = 1 ] && pinenv=(INCURSION_LOWHP_FEAR_PROBE_PIN=1)
    env INCURSION_BIN="$ROOT/incursion-headless" \
        INCURSION_LOWHP_FEAR_PROBE=$mon ${pinenv[@]+"${pinenv[@]}"} \
        INCURSION_RUN_DIR="$rd" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        tools/headless.sh "$keys" 1 > "$rd.harness.txt" 2>&1
    local log="$rd/logs/lowhp-fear.log"
    if [ ! -s "$log" ]; then
        echo "FAIL $name: no probe log (monster never acted?); see $rd.harness.txt"
        status=1; return
    fi
    local acts flees lows immunes
    acts=$(grep -c '^ACT ' "$log")
    flees=$(grep -c '^FLEE-BRANCH ' "$log")
    lows=$(grep '^ACT ' "$log" | grep -c 'lowhp=1')
    immunes=$(grep '^ACT ' "$log" | grep -c 'fearRes=-1')
    echo "  $name: acts=$acts lowhp-acts=$lows fear-immune-acts=$immunes flee-branch=$flees"
    if [ "$pin" = 1 ] && [ "$lows" -lt 1 ]; then
        echo "FAIL $name: monster was never below 1/3 HP; check proves nothing"
        status=1; return
    fi
    if [ "$immune" = 1 ] && [ "$immunes" -lt 1 ]; then
        echo "FAIL $name: monster is not fear-immune; check proves nothing"
        status=1; return
    fi
    if [ "$immune" = 0 ] && [ "$immunes" -gt 0 ]; then
        echo "FAIL $name: control monster is fear-immune; check proves nothing"
        status=1; return
    fi
    if [ "$want" = 1 ] && [ "$flees" -ge 1 ]; then
        echo "PASS $name: flee branch fired"
    elif [ "$want" = 0 ] && [ "$flees" -eq 0 ]; then
        echo "PASS $name: no flee branch"
    else
        echo "FAIL $name: flee-branch=$flees, wanted $([ "$want" = 1 ] && echo ">=1" || echo 0)"
        status=1
    fi
}

run_case IMMUNE  tools/keys/fear-flight-immune.keys 1 0 1
run_case CONTROL tools/keys/fear-flight-plain.keys  1 1 0 bugbear
run_case HEALTHY tools/keys/fear-flight-immune.keys 0 0 1
exit $status
